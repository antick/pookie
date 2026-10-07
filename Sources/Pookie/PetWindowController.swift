import AppKit

/// Owns the pet window, the bubble window, the display link, and every piece of
/// window policy.
///
/// Keeping the policy here means the rest of the app never has to think about
/// Spaces, occlusion, perching, or screen-sharing privacy.
final class PetWindowController {
    let window: PetWindow
    let view: PetView
    let motion: PetMotion

    /// The `say` / `bubble.*` verbs. This is the integration point: M3's socket
    /// server, M4's MCP tools and M5's brain all end up calling `say(_:)`.
    let speech = SpeechEngine()

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var heartbeatElapsed: Double = 0
    private var framesSinceHeartbeat = 0
    private var metrics = ProcessMetrics()
    private var frameAccumulator: Double = 0
    private var targetInterval: Double = 1.0 / 30.0
    private var pendingInterval: Double = 1.0 / 30.0
    private var pendingIntervalDuration: Double = 0

    private let perch = PerchPump()
    private let bubbleWindow: BubbleWindow
    private let bubbleView: BubbleView
    private var lastPerchWindow: Int?
    private var lastBubbleRevision = -1
    private var bubbleSize: CGSize = .zero

    private(set) var isHiddenByUser = false
    private(set) var isRaisedAboveEverything = false

    /// What she is: the cohort hands this out, and the same pair means the same
    /// pet. Neither needs a new window to change — the species is a pose value
    /// and the coat is the renderer's palette.
    private(set) var critter: CritterConfig
    /// Her size relative to the shared setting, so a litter has a kitten in it.
    let personalScale: CGFloat
    /// Ceiling on this pet's drawn frame rate, set by the colony so that N pets
    /// share one budget instead of getting N of them.
    var frameRateCap: Double = 60
    /// The colony she belongs to. Her frame is what pushes the shared clock that
    /// keeps everyone's companion positions fresh, so nobody needs a timer.
    weak var cohort: PetCohort?

    /// The pet's own windows: her body and her bubble.
    var ownWindowNumbers: Set<Int> { [window.windowNumber, bubbleWindow.windowNumber] }

    /// Every pet's windows, so that no cat ever perches on another cat.
    func setExcludedPerchWindows(_ numbers: Set<Int>) {
        perch.excludedWindowNumbers = numbers
        motion.platforms.removeAll { numbers.contains($0.windowNumber) }
    }

    /// A window size for a pet: the shared size setting times her own factor.
    /// Rounded, because the window server expands a fractional frame to whole
    /// points, which would leave the drawing fitted to the wrong box.
    static func windowSize(shared: CGSize, personal: CGFloat) -> CGSize {
        CGSize(width: (shared.width * personal).rounded(), height: (shared.height * personal).rounded())
    }

    init(critter: CritterConfig = .tabbyCat, personalScale: CGFloat = 1, startOrigin: CGPoint? = nil) {
        let config = AppConfig.shared
        self.critter = critter
        self.personalScale = personalScale
        let size = Self.windowSize(shared: config.petSize, personal: personalScale)
        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let start = startOrigin ?? config.startOrigin ?? CGPoint(
            x: screenFrame.maxX - size.width - 80,
            y: screenFrame.minY + 24
        )

        motion = PetMotion(origin: start, size: size, desktop: .current())
        motion.wanderEnabled = config.wanderEnabled
        motion.followCursor = config.followCursor
        motion.perchEnabled = config.perchEnabled
        motion.jumpEnabled = config.jumpEnabled
        motion.teleportEnabled = config.teleportEnabled
        motion.teleportCadence = config.teleportCadence
        motion.species = critter.species
        motion.rescheduleTeleport()

        view = PetView(motion: motion, renderer: CatRenderer(palette: critter.coat.palette))

        // Whole-point origin on purpose: the offset that puts her feet on the
        // floor is fractional, and handing the window server a fractional frame
        // makes it expand the frame to the nearest whole points, which leaves
        // the window a point taller than `motion.size` and the drawing fitted to
        // the wrong box.
        let windowOrigin = CGPoint(
            x: motion.windowOrigin.x.rounded(),
            y: motion.windowOrigin.y.rounded()
        )
        window = PetWindow(
            contentRect: CGRect(origin: windowOrigin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view

        bubbleView = BubbleView(frame: CGRect(origin: .zero, size: CGSize(width: 10, height: 10)))
        bubbleWindow = BubbleWindow(
            contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        bubbleWindow.contentView = bubbleView

        speech.enabled = config.chatty

        view.onTap = { [weak self] in self?.handleTap() }

        configureWindow()
        configureBubbleWindow()
        observeEnvironment()
        startDisplayLink()
    }

    deinit {
        displayLink?.invalidate()
        observers.forEach { $0.center.removeObserver($0.token) }
    }

    /// Take her off the screen for good. The display link holds its target, so a
    /// pet removed from the colony without this would keep drawing forever.
    func close() {
        displayLink?.invalidate()
        displayLink = nil
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
        window.orderOut(nil)
        bubbleWindow.orderOut(nil)
        motion.companions = []
    }

    // MARK: - Window policy

    private func configureWindow() {
        let config = AppConfig.shared

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.acceptsMouseMovedEvents = true
        window.animationBehavior = .none

        // Float above normal windows, ride along to every Space, and stay put
        // during Mission Control. `.ignoresCycle` keeps Pookie out of Cmd-` cycling.
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // `.none` hides the pet from screen sharing and capture. Off by default
        // so screenshots still show Pookie.
        window.sharingType = config.hideFromScreenShare ? .none : .readWrite

        applyClickThroughMode()
        window.orderFrontRegardless()

        Log.info("window up at \(NSStringFromRect(window.frame)) level=\(window.level.rawValue)")
    }

    /// The bubble is a second borderless window: transparent, never key, and
    /// never a mouse target. It sits one level above the pet so it can never be
    /// hidden behind her.
    private func configureBubbleWindow() {
        bubbleWindow.isOpaque = false
        bubbleWindow.backgroundColor = .clear
        bubbleWindow.hasShadow = false
        bubbleWindow.isMovable = false
        bubbleWindow.isMovableByWindowBackground = false
        bubbleWindow.animationBehavior = .none
        bubbleWindow.ignoresMouseEvents = true
        bubbleWindow.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        bubbleWindow.collectionBehavior = window.collectionBehavior
        bubbleWindow.sharingType = window.sharingType

        perch.excludedWindowNumbers = ownWindowNumbers
    }

    func applyClickThroughMode() {
        switch AppConfig.shared.clickThroughMode {
        case .passthrough:
            window.ignoresMouseEvents = true
        case .solid:
            window.ignoresMouseEvents = false
        case .silhouette:
            // Start by ignoring; the frame pump re-enables the mouse as soon as
            // the cursor is over the cat.
            window.ignoresMouseEvents = true
        }
        view.syncMouseState()
        Log.debug("click-through mode = \(AppConfig.shared.clickThroughMode.rawValue)")
    }

    func applyScreenSharePrivacy() {
        window.sharingType = AppConfig.shared.hideFromScreenShare ? .none : .readWrite
    }

    /// Some full-screen apps and screen recorders sit above `.floating`.
    /// `.statusBar` is the escape hatch, short of private APIs.
    func setRaisedAboveEverything(_ raised: Bool) {
        isRaisedAboveEverything = raised
        window.level = raised ? .statusBar : .floating
        window.orderFrontRegardless()
    }

    func setHidden(_ hidden: Bool) {
        isHiddenByUser = hidden
        motion.isPaused = hidden
        if hidden {
            window.orderOut(nil)
            bubbleWindow.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    func toggleHidden() {
        setHidden(!isHiddenByUser)
    }

    func toggleClickThrough() {
        let modes = ClickThroughMode.allCases
        let index = modes.firstIndex(of: AppConfig.shared.clickThroughMode) ?? 0
        AppConfig.shared.clickThroughMode = modes[(index + 1) % modes.count]
        applyClickThroughMode()
        Log.info("click-through mode -> \(AppConfig.shared.clickThroughMode.rawValue)")
    }

    func resetPosition() {
        let region = Desktop.current().region(containing: motion.origin)
        motion.move(
            to: CGPoint(x: region.maxX - motion.size.width - 80, y: region.minY + 24),
            animated: false
        )
    }

    func refreshScreens() {
        motion.desktop = .current()
        // A display that just went away can leave her on a screen that no longer
        // exists, or half off the one that replaced it.
        motion.keepOnScreen()
        Log.debug("screens changed: \(motion.desktop.visibleFrames)")
    }

    func setPerching(_ enabled: Bool) {
        motion.perchEnabled = enabled
        if !enabled { motion.platforms = [] }
    }

    func setJumping(_ enabled: Bool) {
        motion.jumpEnabled = enabled
    }

    /// Apply the size setting.
    ///
    /// The window, the view and the behaviour geometry all change together, so
    /// this is a genuinely bigger or smaller cat rather than a scaled-up
    /// drawing. She keeps her feet on the same spot: the behaviour origin is the
    /// line she stands on, and only the window around it grows.
    func applyPetScale() {
        let size = Self.windowSize(shared: AppConfig.shared.petSize, personal: personalScale)
        guard size != motion.size else { return }

        // The behaviour geometry changes with her: her feet stay on the same
        // spot and only the window around her grows, so nothing has to be
        // recomputed by hand.
        motion.resize(to: size)

        window.setContentSize(size)
        view.frame = CGRect(origin: .zero, size: size)
        view.needsDisplay = true
        syncWindowFrame()

        Log.info("pet size -> \(Int(size.width))x\(Int(size.height)) (\(AppConfig.shared.petScale.label))")
    }

    /// Change what this pet is, without rebuilding her: the species is written
    /// into the pose and the coat is the renderer's palette.
    func apply(critter: CritterConfig) {
        self.critter = critter
        motion.species = critter.species
        view.renderer = CatRenderer(palette: critter.coat.palette)
        view.invalidateMask()
        view.needsDisplay = true
    }

    /// Put the window where the behaviour engine says her feet are.
    func syncWindowFrame() {
        view.syncWindowOrigin()
    }

    func setChatty(_ enabled: Bool) {
        speech.enabled = enabled
        if !enabled { hideBubble() }
    }

    // MARK: - Speech API

    /// Show a line in the bubble. The one call every future producer needs.
    @discardableResult
    func say(
        _ text: String,
        style: BubbleStyle = .plain,
        duration: Double? = nil,
        streaming: Bool = false
    ) -> SpeechOutcome {
        speech.say(text, style: style, duration: duration, streaming: streaming, now: CACurrentMediaTime())
    }

    /// `bubble.append`: stream a delta into the open bubble.
    @discardableResult
    func appendToBubble(_ delta: String, final: Bool = false) -> SpeechOutcome {
        guard let id = speech.bubble?.id else { return .rejected("unknown_bubble") }
        return speech.append(delta, to: id, final: final, now: CACurrentMediaTime())
    }

    func hideBubble() {
        speech.hide(now: CACurrentMediaTime())
    }

    private func handleTap() {
        guard AppConfig.shared.chatty else { return }
        speech.say(PetChatter.tapped(), now: CACurrentMediaTime())
    }

    /// A landing hard enough to be worth a remark, and the occasional word about
    /// a new perch. Everything goes through the same rate limiter, so she can
    /// never turn into a comment machine.
    private func reactToPhysics() {
        let impact = motion.takeLandingImpact()
        let perchWindow = motion.supportPlatform()?.windowNumber
        let isNewPerch = perchWindow != nil && perchWindow != lastPerchWindow
        lastPerchWindow = perchWindow

        guard AppConfig.shared.chatty else { return }

        if impact > 400 {
            speech.say(PetChatter.landed(hard: impact > 900), now: CACurrentMediaTime())
            return
        }

        if isNewPerch, Rand.bool(0.35) {
            let owner = motion.supportPlatform()?.ownerName ?? ""
            speech.say(PetChatter.perched(on: owner), now: CACurrentMediaTime())
        }
    }

    // MARK: - Frame pump

    private func startDisplayLink() {
        guard #available(macOS 14.0, *) else {
            Log.info("display link unavailable; pet will render on demand only")
            return
        }
        let link = view.displayLink(target: self, selector: #selector(onFrame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func onFrame(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTimestamp = now }
        guard lastTimestamp > 0 else { return }
        let elapsed = now - lastTimestamp

        // Hidden or fully occluded: there is nothing to draw and nobody to draw
        // it for, so do not even keep the simulation warm.
        guard !motion.isPaused else { return }

        // A sentence takes a locomotion lock: idle behaviour, jumping included,
        // must not walk out from under it (DESIGN.md §5, rule 4).
        motion.isTalking = speech.isSpeaking

        updateFrameTier(elapsed)

        // Decimate the display link rather than redrawing on every vsync.
        // Software Core Graphics vector rendering is the dominant cost, so the
        // frame budget is the only lever that matters here.
        //
        // The 0.92 tolerance matters: aiming for 30 fps on a 60 Hz clock means
        // waiting exactly two vsyncs, and without slack the accumulated
        // interval falls a hair short on real timestamps and silently takes
        // three, giving 20 fps instead of 30.
        frameAccumulator += elapsed
        guard frameAccumulator >= targetInterval * 0.92 else { return }
        let dt = frameAccumulator
        frameAccumulator = 0

        view.step(dt: dt)

        // Perching may have moved her (a window being dragged carries her), so
        // the window frame is re-synced after the scan.
        perch.update(motion: motion, dt: dt)
        view.syncWindowOrigin()

        // Company, on a clock shared by every pet rather than one per pet.
        cohort?.sync()

        reactToPhysics()
        updateBubble()
        recordHeartbeat(dt)
    }

    /// Pick a frame rate from what the cat is actually doing.
    ///
    /// Two rules, both learned the hard way:
    ///
    /// - **Speeding up is immediate.** The debounce exists to stop a cat on the
    ///   boundary between idle and curious oscillating between tiers; applying
    ///   it to the up-shift as well meant a drag spent its first 0.4 s at the
    ///   idle tier, which reads as the cat lagging behind your hand.
    /// - **Anything the user's hand is driving runs at display rate**, including
    ///   the flight after a throw. That used to fall through to the mood table,
    ///   so a tossed cat fell at 15 fps — the one moment smoothness is obvious.
    private func updateFrameTier(_ dt: Double) {
        let tier = Self.desiredInterval(
            dragging: motion.isDragging,
            airborne: motion.isAirborne,
            // Every short animation runs at 30 fps: the landing squash, the
            // pre-jump crouch, the settle into a loaf, the stretch, and the
            // teleport blink. Drawing any of them at the sleep tier makes them
            // vanish for the wrong reason.
            animating: motion.isSettling || motion.isCrouching
                || motion.isStretching || motion.isChangingShape || motion.isTeleporting,
            overCat: view.isPointerOverPet,
            mood: motion.pose.mood
        )
        // The colony's ceiling is a floor on the interval: ten cats share one
        // budget rather than each taking a full one.
        let desired = max(tier, 1.0 / max(1, frameRateCap))

        if desired != pendingInterval {
            pendingInterval = desired
            pendingIntervalDuration = 0
            if desired < targetInterval {
                targetInterval = desired
                Log.debug("frame tier -> \(Int((1.0 / targetInterval).rounded())) fps (immediate)")
            }
            return
        }

        pendingIntervalDuration += dt
        if pendingInterval != targetInterval, pendingIntervalDuration > 0.4 {
            targetInterval = pendingInterval
            Log.debug("frame tier -> \(Int((1.0 / targetInterval).rounded())) fps")
        }
    }

    /// Exposed for the selftest, which asserts the tier table directly: the bug
    /// this replaced was a tossed cat falling at the idle tier.
    static func desiredInterval(
        dragging: Bool,
        airborne: Bool,
        animating: Bool,
        overCat: Bool,
        mood: CatMood
    ) -> Double {
        if dragging || airborne { return 1.0 / 60.0 }
        if animating { return 1.0 / 30.0 }
        if overCat { return 1.0 / 30.0 }
        switch mood {
        case .walking, .alarmed, .curious, .dragged:
            return 1.0 / 30.0
        case .happy, .thinking:
            return 1.0 / 24.0
        case .sleepy:
            return 1.0 / 8.0
        case .idle:
            return 1.0 / 15.0
        }
    }

    // MARK: - Bubble placement

    /// Anchor the bubble above her head, flipping below when there is no room,
    /// and clamping inside the screen so it never runs off an edge.
    ///
    /// Everything here is cached: text layout is the expensive part, and moving
    /// or resizing a window costs a window-server round trip. While she is idle
    /// with a bubble up, this whole function is a few comparisons.
    private func updateBubble() {
        speech.tick(now: CACurrentMediaTime())

        guard let content = speech.bubble else {
            if bubbleWindow.isVisible { bubbleWindow.orderOut(nil) }
            lastBubbleRevision = -1
            return
        }

        if speech.revision != lastBubbleRevision {
            lastBubbleRevision = speech.revision
            bubbleSize = BubbleRenderer.windowSize(for: content)
        }
        let size = bubbleSize

        let catCenter = CGPoint(
            x: motion.windowOrigin.x + motion.size.width / 2,
            y: motion.windowOrigin.y + motion.size.height / 2
        )
        guard let visible = screen(containing: catCenter)?.visibleFrame else { return }
        let fit = CatGeometry.fit(in: motion.size)
        // Follow the *current* head, so a bubble spoken from a loaf sits on the
        // loaf's head rather than floating where a standing cat's would be.
        let head = motion.pose.anatomy
        let headTop = fit.viewPoint(
            x: head.headCenter.x,
            y: head.headCenter.y + head.headRadius + 2
        )
        let anchor = CGPoint(
            x: motion.windowOrigin.x + headTop.x,
            // Follow the walking bob, so the bubble does not sit on her ears.
            y: motion.windowOrigin.y + headTop.y + CGFloat(motion.pose.hopOffset) * fit.scale
        )
        let gap: CGFloat = 3

        var onBottom = true
        var origin = CGPoint(x: anchor.x - size.width / 2, y: anchor.y + gap)
        if origin.y + size.height > visible.maxY {
            // No room above: flip under her feet and point the tail up.
            onBottom = false
            origin.y = motion.origin.y - size.height - gap
        }
        origin.x = min(max(origin.x, visible.minX + 4), max(visible.minX + 4, visible.maxX - size.width - 4))
        origin.y = min(max(origin.y, visible.minY + 4), max(visible.minY + 4, visible.maxY - size.height - 4))

        bubbleView.update(content: content, revision: speech.revision)
        bubbleView.setTail(x: anchor.x - origin.x, onBottom: onBottom)

        let level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        if bubbleWindow.level != level { bubbleWindow.level = level }
        if bubbleWindow.sharingType != window.sharingType { bubbleWindow.sharingType = window.sharingType }

        let frame = CGRect(origin: origin, size: size)
        if bubbleWindow.frame != frame {
            bubbleWindow.setFrame(frame, display: false)
        }
        if !bubbleWindow.isVisible, !isHiddenByUser {
            bubbleWindow.orderFrontRegardless()
        }
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Under `--verbose`, prove the frame pump is alive and the cat is moving.
    /// Doubles as the cheapest battery regression test: if idle fps is not
    /// low, something is animating that should not be.
    private func recordHeartbeat(_ dt: Double) {
        guard Log.verbose else { return }
        heartbeatElapsed += dt
        framesSinceHeartbeat += 1
        guard heartbeatElapsed >= 2 else { return }

        let fps = Double(framesSinceHeartbeat) / heartbeatElapsed
        let cpu = metrics.cpuPercent(now: CACurrentMediaTime())
        let perch = motion.supportPlatform().map { "\($0.ownerName)#\($0.windowNumber)" } ?? "floor"
        Log.info(
            "[\(critter.species.rawValue):\(critter.coat.rawValue)] "
            + "drawn=\(String(format: "%.1f", fps))fps "
            + "tier=\(String(format: "%.0f", (1.0 / targetInterval).rounded()))fps "
            + "cpu=\(String(format: "%.1f", cpu))% "
            + "rss=\(String(format: "%.0f", ProcessMetrics.residentMegabytes()))MB "
            + "mood=\(motion.pose.mood.rawValue) "
            + "shape=\(motion.shape.rawValue) "
            + "resting=\(motion.isResting ? "yes" : "no") "
            + String(format: "stretch=%.2f ", motion.pose.shape.stretch)
            + "origin=(\(Int(motion.origin.x)), \(Int(motion.origin.y))) "
            + "perch=\(perch) "
            + "platforms=\(motion.platforms.count) "
            + "jumps=\(motion.jumpCount) "
            + "hops=\(motion.teleportCount) "
            + "plays=\(motion.playCount) "
            + "scraps=\(motion.scuffleCount) "
            + "bubble=\(speech.bubble == nil ? "no" : "yes") "
            + "paused=\(motion.isPaused) "
            + "overCat=\(view.isPointerOverPet)"
        )
        heartbeatElapsed = 0
        framesSinceHeartbeat = 0
    }

    // MARK: - Environment

    private func observeEnvironment() {
        let center = NotificationCenter.default

        observers.append((center, center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshScreens()
        }))

        // Stop animating when the pet is not actually on screen. An always-on
        // 60fps window is a battery crime.
        observers.append((center, center.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let visible = self.window.occlusionState.contains(.visible)
            self.motion.isPaused = !visible || self.isHiddenByUser
            Log.debug("occlusion changed, visible=\(visible)")
        }))

        // A window that just came forward is the likeliest new perch, so refresh
        // straight away instead of waiting for the next slow sweep.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.motion.perchEnabled, !self.motion.isPaused else { return }
            self.perch.refresh(motion: self.motion)
        }))
    }
}
