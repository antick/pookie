import Foundation

/// The control plane's transport: NDJSON over a Unix domain socket, with a
/// loopback TCP fallback (`PROTOCOL.md` §1).
///
/// Deliberately BSD sockets rather than `NWListener`: the protocol is a Unix
/// domain socket, `Network.framework`'s support for one is a corner rather than a
/// road, and the two things this file has to get right — not binding over a socket
/// a live instance still owns, and not leaving the socket world-writable — are
/// visible here rather than buried.
///
/// Everything decidable lives in `IntentRouter`; this file reads lines, asks the
/// router, writes the ack back, and does nothing else. It is testable headlessly,
/// which is why the tests connect to a real socket in a temporary directory.

/// One connection's framing: bytes in, lines out.
final class ControlConnection {
    let fd: Int32
    private let queue: DispatchQueue
    private var buffer = Data()
    private var source: DispatchSourceRead?
    /// Whether the client asked for acks. A client that never sent `hello` gets
    /// none: `PROTOCOL.md` §1.
    var wantsAcks = false
    var clientName: String?
    /// Events this connection asked for (`pet.on`). `"*"` means all of them.
    var subscriptions: Set<String> = []
    /// The label the client gave, echoed on every event so a multiplexed client can
    /// route (`PROTOCOL.md` §6).
    var handlerLabel: String = "default"
    private(set) var isClosed = false

    /// One line received. The reply is written back if there is one.
    var onLine: ((String, ControlConnection) -> String?)?

    init(fd: Int32, queue: DispatchQueue) {
        self.fd = fd
        self.queue = queue
    }

    func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { [weak self] in
            guard let self, !isClosed else { return }
            isClosed = true
            Darwin.close(fd)
        }
        self.source = source
        source.resume()
    }

    /// Write one line, newline-terminated.
    func send(_ line: String) {
        guard !isClosed else { return }
        let bytes = Array((line + "\n").utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return write(fd, base.advanced(by: offset), bytes.count - offset)
            }
            if written > 0 {
                offset += written
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                // The socket buffer is full. A pet's acks are tiny and rare, so
                // rather than queueing, drop this one and say so in the log.
                Log.info("control: a client is not reading its acks; dropping one")
                return
            } else {
                closeConnection()
                return
            }
        }
    }

    /// One event line, if this connection asked for that event.
    ///
    /// Events are at-most-once and never replayed: a reconnecting client loses what it
    /// missed, and the protocol says so.
    func sendEvent(_ event: String, pet: String, data: [String: Any]) {
        guard !isClosed else { return }
        guard subscriptions.contains(event) || subscriptions.contains("*") else { return }
        let fields = data
            .sorted { $0.key < $1.key }
            .map { key, value in "\"\(key)\":\(CLI.json(value))" }
            .joined(separator: ",")
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        send("{\"event\":\"\(event)\",\"ts\":\(timestamp),\"pet\":\(CLI.json(pet)),\"handler\":\(CLI.json(handlerLabel)),\"data\":{\(fields)}}")
    }

    func closeConnection() {
        guard !isClosed else { return }
        isClosed = true
        source?.cancel()
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let capacity = chunk.count
        let read = chunk.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return recv(fd, base, capacity, 0)
        }
        guard read > 0 else {
            // A readable socket that has nothing to give is a spurious wake-up, not
            // a disconnect: the read source only fires when it is readable, but
            // treating EAGAIN as "closed" would drop a healthy connection.
            if read < 0, errno == EAGAIN || errno == EWOULDBLOCK { return }
            // Zero is a clean disconnect; anything else is a broken one. Either way
            // the connection is done.
            closeConnection()
            return
        }
        buffer.append(contentsOf: chunk[0..<read])

        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let line = String(data: lineData, encoding: .utf8) else {
                send("{\"id\":\"\",\"ok\":false,\"error\":\"malformed_json\"}")
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let reply = onLine?(trimmed, self), wantsAcks || reply.hasPrefix("{\"verb\":\"hello.ok\"") {
                send(reply)
            }
        }
    }
}

/// The listening socket, the connections, and the routing between them.
final class ControlServer {
    /// Where the socket lives. `PROTOCOL.md` §1 names it, and a client needs to
    /// find it without configuration.
    static var defaultDirectory: String {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.path ?? NSHomeDirectory() + "/Library/Application Support"
        return base + "/Pookie"
    }
    /// The protocol's path, unless the environment names another one. An override is
    /// not decoration: a test, or a second instance for a demo, needs its own socket
    /// without fighting the real one for it.
    static var defaultSocketPath: String {
        if let override = ProcessInfo.processInfo.environment["POOKIE_CONTROL_SOCKET"], !override.isEmpty {
            return override
        }
        return defaultDirectory + "/control.sock"
    }
    static var defaultPortPath: String { defaultDirectory + "/port" }

    private let socketPath: String
    private let portPath: String?
    private let queue = DispatchQueue(label: "pookie.control")
    private let router = IntentRouter()
    private var listeningFD: Int32 = -1
    private var tcpFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var tcpSource: DispatchSourceRead?
    private var connections: [ControlConnection] = []

    /// Called for each accepted intent. The reply is written back down the
    /// connection.
    var handler: ((Intent) -> IntentAck)?

    /// Send an event to every connection that asked for it.
    func emit(_ event: String, pet: String, data: [String: Any]) {
        queue.async { [weak self] in
            guard let self else { return }
            for connection in connections {
                connection.sendEvent(event, pet: pet, data: data)
            }
        }
    }

    /// The loopback port, once started, for the log line and the port file.
    private(set) var port: UInt16?

    /// The version reported in `hello.ok`.
    var version = "0.1"

    /// Names of the pets that exist, for `hello.ok`.
    var petNames: () -> [String] = { [] }

    init(socketPath: String = ControlServer.defaultSocketPath, portPath: String? = ControlServer.defaultPortPath) {
        self.socketPath = socketPath
        self.portPath = portPath
    }

    // MARK: - Lifecycle

    /// Bind and listen. Throws with a readable reason rather than logging, because
    /// the caller decides whether a pet without a control socket is fatal.
    func start() throws {
        // The directory is created, and a failure to create it is *reported*: the
        // bind error that follows is "no such file or directory", which tells a user
        // nothing about why.
        let directory = (socketPath as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: directory) {
            do {
                try FileManager.default.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o755]
                )
            } catch {
                throw ControlError.cannotCreateDirectory(directory, error.localizedDescription)
            }
        }

        try prepareSocketPath()
        listeningFD = try bindUnix(path: socketPath)
        // Only the user may talk to their pet. The umask is not to be trusted for
        // this: a world-writable control socket is a stranger animating your cat.
        chmod(socketPath, 0o600)
        guard listen(listeningFD, 16) == 0 else {
            throw ControlError.cannotListen(errno)
        }
        // Non-blocking, and this is not a detail: the accept loop drains until
        // `accept` says there is nothing left, and on a blocking socket that call
        // *waits*. The listener shares its serial queue with every connection's read
        // source, so a blocking accept wedges the whole server after the first
        // client — connected, silent, and apparently healthy.
        setNonBlocking(listeningFD)
        acceptSource = makeAcceptSource(fd: listeningFD)
        Log.info("control: listening on \(socketPath) (mode 0600)")

        // The fallback, for clients that handle TCP better than Unix sockets. Its
        // port is written where the protocol says to find it.
        if let portPath, let tcp = try? bindLoopback() {
            tcpFD = tcp.fd
            port = tcp.port
            setNonBlocking(tcpFD)
            tcpSource = makeAcceptSource(fd: tcpFD)
            try? "\(tcp.port)\n".write(toFile: portPath, atomically: true, encoding: .utf8)
            chmod(portPath, 0o600)
            Log.info("control: also listening on 127.0.0.1:\(tcp.port)")
        }
    }

    /// Close everything and remove the socket, so the next instance binds cleanly.
    func stop() {
        for connection in connections { connection.closeConnection() }
        connections.removeAll()
        acceptSource?.cancel()
        tcpSource?.cancel()
        if listeningFD >= 0 { close(listeningFD); listeningFD = -1 }
        if tcpFD >= 0 { close(tcpFD); tcpFD = -1 }
        try? FileManager.default.removeItem(atPath: socketPath)
        if let portPath { try? FileManager.default.removeItem(atPath: portPath) }
    }

    /// A socket file on disk is not the same as a socket somebody is listening on.
    ///
    /// A crashed instance leaves the file behind, and binding over it fails with
    /// `EADDRINUSE` — which is how a pet ends up unable to start with a message
    /// about an address in use and nobody to blame. So: if the path exists, try to
    /// connect to it. A refused connection means it is stale and can go; a
    /// successful one means a live instance owns it and this one must not steal it.
    private func prepareSocketPath() throws {
        guard FileManager.default.fileExists(atPath: socketPath) else { return }

        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { if probe >= 0 { close(probe) } }
        if probe >= 0, connectUnix(fd: probe, path: socketPath) == 0 {
            throw ControlError.alreadyRunning(socketPath)
        }
        Log.info("control: removing a stale socket at \(socketPath)")
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    // MARK: - Accepting

    private func makeAcceptSource(fd: Int32) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending(on: fd) }
        source.resume()
        return source
    }

    private func acceptPending(on fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else {
                if errno != EAGAIN && errno != EWOULDBLOCK {
                    Log.info("control: accept failed: \(String(cString: strerror(errno)))")
                }
                return
            }
            // Non-blocking, so a client that stops reading cannot wedge the pet's
            // main queue.
            setNonBlocking(client)

            let connection = ControlConnection(fd: client, queue: queue)
            connection.onLine = { [weak self] line, connection in
                self?.handle(line: line, from: connection)
            }
            connections.append(connection)
            connection.start()
        }
    }

    /// One line from a client: the handshake, or an intent.
    private func handle(line: String, from connection: ControlConnection) -> String? {
        if let hello = HelloRequest(line: line) {
            connection.wantsAcks = hello.wantsAcks
            connection.clientName = hello.client
            let pets = petNames().map { "\"\($0)\"" }.joined(separator: ",")
            return "{\"verb\":\"hello.ok\",\"args\":{\"protocol\":\"\(version)\",\"pets\":[\(pets)],\"version\":\"\(version)\"}}"
        }

        let (ack, intent) = router.receiveResult(line: line, now: Date().timeIntervalSince1970 * 1000)
        guard ack.ok, let intent else { return ack.line }

        // `pet.on` is the one verb the transport answers itself: a subscription belongs
        // to the connection, not to the pet, and the behaviour layer has no business
        // knowing which socket asked.
        if intent.verb == .petOn {
            let wanted: [String]
            if let one = intent.args["event"] as? String {
                wanted = [one]
            } else if let many = intent.args["event"] as? [String] {
                wanted = many
            } else {
                return IntentAck.refused(intent.id, .badArgs).line
            }
            connection.subscriptions.formUnion(wanted)
            if let label = intent.args["handler"] as? String {
                connection.handlerLabel = label
            }
            Log.info("control: \(connection.clientName ?? "a client") subscribed to \(wanted.joined(separator: ", "))")
            return IntentAck.started(intent.id).line
        }

        guard let handler else { return ack.line }
        return handler(intent).line
    }
}

/// The optional first line: `PROTOCOL.md` §1.
struct HelloRequest {
    var client: String?
    /// Events are opt-in, and a client that sends `hello` without asking for them
    /// gets none.
    var events: [String] = []
    /// Acks are opt-in too. A client that never says `hello` is assumed to want
    /// neither events nor acks.
    var wantsAcks = true

    init?(line: String) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["verb"] as? String == "hello"
        else { return nil }
        let args = object["args"] as? [String: Any] ?? [:]
        client = args["client"] as? String
        events = args["events"] as? [String] ?? []
        wantsAcks = true
    }
}

enum ControlError: Error, CustomStringConvertible {
    case cannotCreateDirectory(String, String)
    case cannotBind(String, Int32)
    case cannotListen(Int32)
    case alreadyRunning(String)

    var description: String {
        switch self {
        case .cannotCreateDirectory(let path, let reason):
            return "could not create \(path): \(reason)"
        case .cannotBind(let path, let code):
            return "could not bind \(path): \(String(cString: strerror(code)))"
        case .cannotListen(let code):
            return "could not listen: \(String(cString: strerror(code)))"
        case .alreadyRunning(let path):
            return "another Pookie is already listening on \(path)"
        }
    }
}

// MARK: - The POSIX bits

private func setNonBlocking(_ fd: Int32) {
    let flags = fcntl(fd, F_GETFL, 0)
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
}

/// Fill a `sockaddr_un` with `path`, then call `body` with it.
private func withUnixAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T? {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard path.utf8.count < capacity else { return nil }
    withUnsafeMutablePointer(to: &address.sun_path) { tuple in
        tuple.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
            _ = strlcpy(destination, path, capacity)
        }
    }
    return withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            body(socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
}

private func bindUnix(path: String) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw ControlError.cannotBind(path, errno) }
    guard let bound = withUnixAddress(path, { bind(fd, $0, $1) }), bound == 0 else {
        let code = errno
        close(fd)
        throw ControlError.cannotBind(path, code)
    }
    return fd
}

private func connectUnix(fd: Int32, path: String) -> Int32 {
    withUnixAddress(path, { connect(fd, $0, $1) }) ?? -1
}

/// `127.0.0.1` on an ephemeral port, reported back through `getsockname`.
private func bindLoopback() throws -> (fd: Int32, port: UInt16) {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw ControlError.cannotBind("127.0.0.1", errno) }

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
    let bound = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bound == 0, listen(fd, 16) == 0 else {
        let code = errno
        close(fd)
        throw ControlError.cannotBind("127.0.0.1", code)
    }

    var actual = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &actual) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            getsockname(fd, socketAddress, &length)
        }
    }
    guard named == 0 else {
        close(fd)
        throw ControlError.cannotBind("127.0.0.1", errno)
    }
    return (fd, UInt16(bigEndian: actual.sin_port))
}

// MARK: - The client

/// The other end: what the `pookie` CLI uses, and what the tests connect with.
final class ControlClient {
    private let fd: Int32
    private var buffer = Data()

    /// Connect to a running pet's control socket. Throws when there is nothing to
    /// talk to, which is the CLI's most common failure and deserves a clear message.
    init(socketPath: String = ControlServer.defaultSocketPath) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlError.cannotBind(socketPath, errno) }
        guard connectUnix(fd: fd, path: socketPath) == 0 else {
            let code = errno
            Darwin.close(fd)
            throw ControlError.cannotBind(socketPath, code)
        }
        self.fd = fd
    }

    func send(_ line: String) {
        let bytes = Array((line + "\n").utf8)
        _ = bytes.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return write(fd, base, bytes.count)
        }
    }

    /// Read one line, waiting at most `timeout` seconds. A `select` rather than a
    /// blocking read, because a test that hangs is worse than one that fails.
    func readLine(timeout: Double) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                return String(data: lineData, encoding: .utf8)
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }

            var readSet = fd_set()
            withUnsafeMutablePointer(to: &readSet) { pointer in
                pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<fd_set>.size) { bytes in
                    memset(bytes, 0, MemoryLayout<fd_set>.size)
                }
            }
            let width = fd + 1
            withUnsafeMutablePointer(to: &readSet.fds_bits) { tuple in
                tuple.withMemoryRebound(to: Int32.self, capacity: 32) { words in
                    words[Int(fd) / 32] |= Int32(1 << (Int(fd) % 32))
                }
            }
            var timeoutValue = timeval(tv_sec: Int(remaining), tv_usec: Int32((remaining - Double(Int(remaining))) * 1_000_000))
            let ready = withUnsafeMutablePointer(to: &readSet) { pointer in
                select(width, pointer, nil, nil, &timeoutValue)
            }
            guard ready > 0 else { continue }

            var chunk = [UInt8](repeating: 0, count: 4096)
            let capacity = chunk.count
            let read = chunk.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return recv(fd, base, capacity, 0)
            }
            guard read > 0 else { return nil }
            buffer.append(contentsOf: chunk[0..<read])
        }
    }

    func close() {
        Darwin.close(fd)
    }
}
