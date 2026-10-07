import AppKit

/// Renders Pookie and turns raw mouse events into motion input.
///
/// All it knows how to do is draw a pose and report which pixels it covered;
/// the behaviour lives in `PetMotion` and the window policy lives in
/// `PetWindowController`.
final class PetView: NSView {
    let motion: PetMotion
    var renderer: CatRenderer

    /// Called when the cat is tapped rather than dragged: a press and release in
    /// roughly the same place. This is the `clicked` / `petted` event from
    /// `DESIGN.md`, and the hook the bubble hangs off.
    var onTap: (() -> Void)?

    private var mask: AlphaMask?
    private var maskSize: CGSize = .zero
    private var maskRefreshCountdown: Double = 0
    private var isCurrentlyIgnoringMouse = false
    private var pressPoint: CGPoint?
    private var pressTime: Double = 0

    /// Whether the pointer is over the cat right now. Reported for the M4
    /// event stream (`petted`, `hovered`).
    private(set) var isPointerOverPet = false

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    /// Without this, the first click on an inactive window is swallowed to
    /// "activate" it, and Pookie feels unresponsive.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(motion: PetMotion, renderer: CatRenderer) {
        self.motion = motion
        self.renderer = renderer
        super.init(frame: CGRect(origin: .zero, size: motion.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        renderer.draw(in: context, size: bounds.size, pose: motion.pose)
    }

    /// Called once per display refresh by `PetWindowController`.
    func step(dt: Double) {
        motion.cursor = NSEvent.mouseLocation
        motion.advance(dt: dt)

        updateMousePassthrough(dt: dt)
        syncWindowOrigin()
        needsDisplay = true
    }

    /// Keep the window where the behaviour engine says the cat is. Called again
    /// after the perch pump, which can move her with a window she is riding.
    ///
    /// `motion.origin` is the line her feet are on, not the corner of her
    /// window: `windowOrigin` subtracts the transparent margin the renderer
    /// keeps below her paws, so she stands on a window top rather than a few
    /// points above it.
    func syncWindowOrigin() {
        guard let window else { return }
        // Snap before comparing. The offset that puts her feet on the floor is
        // fractional (it scales with her size), the window server rounds the
        // frame to whole points anyway, and a fractional target would make this
        // a window-server round trip on every single frame.
        let target = motion.windowOrigin
        let snapped = CGPoint(x: target.x.rounded(), y: target.y.rounded())
        if window.frame.origin != snapped {
            window.setFrameOrigin(snapped)
        }
    }

    // MARK: - Mouse pass-through
    //
    // The honest implementation of "click through the gaps": keep the window
    // ignoring the mouse, and re-enable it only while the cursor is actually
    // over the cat. Polling `NSEvent.mouseLocation` is free and needs no
    // permission, and the frame pump already runs at display rate, so the
    // worst-case latency is one frame.

    private func updateMousePassthrough(dt: Double) {
        guard let window else { return }

        let shouldIgnore: Bool
        switch AppConfig.shared.clickThroughMode {
        case .passthrough:
            shouldIgnore = true
            isPointerOverPet = false
        case .solid:
            shouldIgnore = false
            isPointerOverPet = true
        case .silhouette:
            // Never drop the mouse mid-drag, or the cat escapes your hand.
            if motion.isDragging {
                shouldIgnore = false
                isPointerOverPet = true
            } else {
                refreshMaskIfNeeded(dt: dt)
                let mouse = NSEvent.mouseLocation
                let frame = window.frame
                let local = CGPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY)
                let inside = mask?.isOpaque(near: local, radius: 3) ?? false
                shouldIgnore = !inside
                isPointerOverPet = inside
            }
        }

        guard shouldIgnore != isCurrentlyIgnoringMouse else { return }
        isCurrentlyIgnoringMouse = shouldIgnore
        window.ignoresMouseEvents = shouldIgnore
    }

    // MARK: - Hit testing

    /// Secondary guard. The pass-through pump above is what actually makes
    /// clicks reach the app underneath; this stops a click that lands in a gap
    /// from activating the window on the frame the cursor leaves the cat.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: nil)
        switch AppConfig.shared.clickThroughMode {
        case .passthrough:
            return nil
        case .solid:
            return bounds.contains(local) ? self : nil
        case .silhouette:
            guard bounds.contains(local) else { return nil }
            refreshMaskIfNeeded(dt: 1.0 / 60.0)
            // The same small tolerance the pass-through pump uses, so a click
            // right on the outline is not swallowed.
            guard let mask, mask.isOpaque(near: local, radius: 2) else { return nil }
            return self
        }
    }

    /// Builds this pet's right-click menu, on demand.
    ///
    /// The menu belongs to the app shell, which is the only thing that knows the
    /// colony, so the view carries a hook rather than a reference. That keeps the
    /// drawing layer free of the menu and lets the shell assemble the same items
    /// the menu bar uses.
    var makeContextMenu: (() -> NSMenu?)?

    /// Right-clicking a pet deals with *that* pet.
    ///
    /// Until this existed, the only way to take an animal off the desk was the
    /// menu bar's remove, which always took the newest one — so hiding the middle
    /// of a colony meant removing everything above it.
    override func menu(for event: NSEvent) -> NSMenu? {
        makeContextMenu?()
    }

    /// Forget the cached silhouette. Changing what an animal *is* — its species
    /// or its coat — changes the shape the mouse pass-through tests against, and
    /// the cache would otherwise be a half second stale.
    func invalidateMask() {
        mask = nil
    }

    /// Re-sync the cached pass-through state after the mode changes out from
    /// under the frame pump.
    func syncMouseState() {
        isCurrentlyIgnoringMouse = window?.ignoresMouseEvents ?? false
    }

    private func refreshMaskIfNeeded(dt: Double) {
        if mask == nil || maskSize != bounds.size {
            mask = MaskRaster.make(renderer: renderer, size: bounds.size, pose: .neutral)
            maskSize = bounds.size
            maskRefreshCountdown = 0.5
            return
        }
        // Rasterising the silhouette is not free. Twice a second is plenty for
        // deciding whether the cursor is over the cat — and the countdown is in
        // seconds, not frames, so a sleepy cat at 8 fps refreshes it just as
        // often as a dragged one at 60.
        maskRefreshCountdown -= dt
        guard maskRefreshCountdown <= 0 else { return }
        maskRefreshCountdown = 0.5
        mask = MaskRaster.make(renderer: renderer, size: bounds.size, pose: motion.pose)
    }

    // MARK: - Input

    override func mouseDown(with event: NSEvent) {
        pressPoint = NSEvent.mouseLocation
        pressTime = event.timestamp
        motion.beginDrag(at: NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        motion.updateDrag(to: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        motion.endDrag()

        // A press and release in the same spot is a tap, not a throw. Without
        // this the cat can only ever be dragged, never petted.
        defer { pressPoint = nil }
        guard let pressPoint else { return }
        if Self.isTap(from: pressPoint, to: NSEvent.mouseLocation, held: event.timestamp - pressTime) {
            onTap?()
        }
    }

    /// Pure, so the selftest can pin the threshold without synthesising events.
    static func isTap(from press: CGPoint, to release: CGPoint, held: Double) -> Bool {
        let moved = hypot(release.x - press.x, release.y - press.y)
        return moved < 4 && held < 0.4
    }
}
