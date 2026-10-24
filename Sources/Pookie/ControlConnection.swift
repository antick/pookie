import Foundation

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
