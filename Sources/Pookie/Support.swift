import AppKit
import CoreGraphics
import Darwin

// MARK: - Small shared utilities

/// Self-reported CPU and memory, so energy claims can be checked from inside
/// the process. External tools like `ps` are not always available, and M1's
/// frame-rate tiers need a way to prove they helped.
struct ProcessMetrics {
    private var lastCPUSeconds: Double?
    private var lastSampleTime: Double?

    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    static func residentMegabytes() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576
    }

    /// Percentage of a single core since the previous call. Returns 0 on the
    /// first call, which is the baseline sample.
    mutating func cpuPercent(now: Double) -> Double {
        let cpu = Self.cpuSeconds()
        defer {
            lastCPUSeconds = cpu
            lastSampleTime = now
        }
        guard let previousCPU = lastCPUSeconds, let previousTime = lastSampleTime else { return 0 }
        let wall = now - previousTime
        guard wall > 0 else { return 0 }
        return (cpu - previousCPU) / wall * 100
    }
}

extension CGColor {
    /// Build an sRGB color from a hex literal, e.g. `CGColor.hex(0xF2A25C)`.
    static func hex(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

extension NSColor {
    /// The AppKit twin of `CGColor.hex`, for the bubble's palette.
    static func hex(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

enum Log {
    static var verbose = false

    static func info(_ message: String) {
        FileHandle.standardError.write(Data("[pookie] \(message)\n".utf8))
    }

    static func debug(_ message: String) {
        guard verbose else { return }
        info(message)
    }
}

/// Deterministic-ish randomness helpers so motion code stays readable.
enum Rand {
    static func double(_ range: ClosedRange<Double>) -> Double {
        Double.random(in: range)
    }

    static func cg(_ range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat.random(in: range)
    }

    static func bool(_ probability: Double = 0.5) -> Bool {
        Double.random(in: 0..<1) < probability
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

extension Collection {
    /// The element at `index`, or nil when it is out of bounds.
    ///
    /// Menu items carry an index into the colony and can outlive the pet they
    /// point at — the menu is rebuilt on every action, but validation walks it
    /// first.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// A screen's usable region (excludes the menu bar and the Dock).
struct Desktop {
    var visibleFrames: [CGRect]

    static func current() -> Desktop {
        let frames = NSScreen.screens.map(\.visibleFrame)
        return Desktop(visibleFrames: frames.isEmpty ? [CGRect(x: 0, y: 0, width: 1440, height: 900)] : frames)
    }

    /// The usable region containing `point`, or the region containing the point
    /// with the largest overlap, falling back to the first screen.
    func region(containing point: CGPoint) -> CGRect {
        if let exact = visibleFrames.first(where: { $0.contains(point) }) {
            return exact
        }
        let best = visibleFrames.max { a, b in
            let da = hypot(a.midX - point.x, a.midY - point.y)
            let db = hypot(b.midX - point.x, b.midY - point.y)
            return da > db
        }
        return best ?? visibleFrames[0]
    }
}
