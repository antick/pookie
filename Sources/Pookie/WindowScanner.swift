import AppKit
import CoreGraphics

/// Finds the top edges of other apps' windows for the cat to stand on.
///
/// **Permission-free by construction.** `CGWindowListCopyWindowInfo` reports a
/// window's owner, bounds and layer without Screen Recording permission; only
/// the *title* (`kCGWindowName`) is gated. So this deliberately never reads
/// titles and never asks for anything — see `docs/MACOS-CONSTRAINTS.md` §4.3.
///
/// Coordinate space: `CGWindowList` bounds are top-left-origin global
/// coordinates with y increasing downward, while AppKit is bottom-left-origin.
/// The conversion happens in exactly one place, here, because mixing the two is
/// the classic "the cat is one screen-height off" bug (same doc, §6).
enum WindowScanner {
    /// Normal-layer, on-screen windows big enough to hold a cat.
    static func platforms(excludingWindowNumbers excluded: Set<Int>) -> [WindowPlatform] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        // The primary display's height is the y-flip origin. `NSScreen.screens`
        // puts the display with the menu bar first, and its frame origin is
        // (0, 0) by definition.
        let flipHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let ownPID = ProcessInfo.processInfo.processIdentifier

        var result: [WindowPlatform] = []
        result.reserveCapacity(raw.count)

        for info in raw {
            guard let number = info[kCGWindowNumber as String] as? Int,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  !excluded.contains(number),
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID != ownPID,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }

            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }

            // Too small to stand on: tooltips, palettes, HUDs. A perch also has
            // to be wider than the cat or she would slip off instantly.
            guard cgRect.width >= 120, cgRect.height >= 60 else { continue }

            let appKitRect = CGRect(
                x: cgRect.minX,
                y: flipHeight - cgRect.maxY,
                width: cgRect.width,
                height: cgRect.height
            )

            result.append(
                WindowPlatform(
                    windowNumber: number,
                    ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
                    rect: appKitRect
                )
            )
        }
        return result
    }
}

/// Keeps `PetMotion.platforms` fresh, and carries the cat along when the window
/// she is standing on is dragged.
///
/// The DESIGN rule is "no per-frame window-list scans", so this runs on its own
/// clock: a slow sweep normally, a fast one only while she is actually perched
/// on something, because that is the one case where the geometry has to track
/// another app in real time.
final class PerchPump {
    /// How often the window list is re-read, in seconds.
    static let idleInterval: Double = 1.0
    static let perchedInterval: Double = 0.1
    /// While she is in the air the list has to be fresh enough that she lands on
    /// a window rather than through it — and she covers a lot of ground in a
    /// second of falling.
    static let airborneInterval: Double = 0.2

    /// Windows that belong to Pookie: never perches.
    var excludedWindowNumbers: Set<Int> = []

    /// The window-list source. Injectable so the pump's cadence and riding logic
    /// can be tested without a window server.
    var scan: (Set<Int>) -> [WindowPlatform] = WindowScanner.platforms

    private var knownRects: [Int: CGRect] = [:]
    /// Starts overdue so the very first frame after launch has the window list.
    /// Without this she spawns, falls for up to a second with no platforms known,
    /// and drops straight past the window she was supposed to land on.
    private var elapsed: Double = .greatestFiniteMagnitude
    private(set) var lastScanCount = 0

    /// Advance the pump. Returns true when the platform list was refreshed.
    @discardableResult
    func update(motion: PetMotion, dt: Double) -> Bool {
        guard motion.perchEnabled else {
            if !motion.platforms.isEmpty {
                motion.platforms = []
                knownRects.removeAll()
            }
            return false
        }

        elapsed += dt
        let interval: Double
        if motion.supportPlatform() != nil {
            interval = Self.perchedInterval
        } else if motion.isAirborne {
            interval = Self.airborneInterval
        } else {
            interval = Self.idleInterval
        }
        guard elapsed >= interval else { return false }
        elapsed = 0
        refresh(motion: motion)
        return true
    }

    func refresh(motion: PetMotion) {
        let platforms = scan(excludedWindowNumbers)
        lastScanCount = platforms.count

        // Which app is in front is permission-free and is the best available
        // guess at which window the user cares about. It only biases her choice
        // of ledge; it is not a requirement for jumping.
        motion.preferredPlatformOwner = NSWorkspace.shared.frontmostApplication?.localizedName

        // Ride first: compare where her perch was with where it is now, and move
        // her by the same delta. Without this, dragging a window out from under
        // her leaves her standing on nothing.
        if let perch = motion.supportPlatform(),
           let before = knownRects[perch.windowNumber],
           let after = platforms.first(where: { $0.windowNumber == perch.windowNumber }) {
            let dx = after.rect.minX - before.minX
            let dy = after.rect.maxY - before.maxY
            motion.ride(dx: dx, dy: dy)
        }

        var rects: [Int: CGRect] = [:]
        rects.reserveCapacity(platforms.count)
        for platform in platforms {
            rects[platform.windowNumber] = platform.rect
        }
        knownRects = rects
        motion.platforms = platforms
    }
}
