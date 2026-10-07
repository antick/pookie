import AppKit

/// Borderless, transparent, and — critically — incapable of becoming key.
///
/// A desktop pet that steals focus is a desktop pet that gets uninstalled.
/// Overriding these two properties is the single most important line of
/// defence; see `docs/MACOS-CONSTRAINTS.md`.
final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}
