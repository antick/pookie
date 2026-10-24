import Foundation

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
            _ = withUnsafeMutablePointer(to: &readSet) { pointer in
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
