import CoreGraphics
import Foundation

/// The top edge of another app's window, as a place the cat can stand.
///
/// Geometry only: `WindowScanner` gets these from `CGWindowListCopyWindowInfo`,
/// which reports owner, bounds and layer **without** Screen Recording
/// permission. Titles are deliberately not used — they are the field that needs
/// the permission. See `docs/MACOS-CONSTRAINTS.md` §4.3.
struct WindowPlatform: Equatable {
    var windowNumber: Int
    var ownerName: String
    /// The window's frame in AppKit screen coordinates (origin bottom-left).
    var rect: CGRect

    /// Slack at each end so she can stand with her feet slightly overhanging an
    /// edge without dropping the instant her centre crosses it.
    static let edgeSlack: CGFloat = 6

    var top: CGFloat { rect.maxY }

    func spans(_ x: CGFloat) -> Bool {
        x >= rect.minX - Self.edgeSlack && x <= rect.maxX + Self.edgeSlack
    }
}

/// The whole of Pookie's M0 behaviour: fake physics plus the idle life signs
/// that make the cat feel alive.
///
/// Deliberately free of AppKit so it can be unit-tested, replayed, and later
/// driven by the intent protocol instead of by mouse events. The view feeds it
/// input and reads `origin` and `pose` back out.
final class PetMotion {
    // Configuration
    var size: CGSize
    var desktop: Desktop
    var wanderEnabled = true
    var followCursor = true
    /// When true she lands on the top edges of other apps' windows instead of
    /// falling straight past them to the bottom of the screen.
    var perchEnabled = true
    /// When true she also *jumps* up onto a window top by herself, rather than
    /// only perching when you drop her there.
    var jumpEnabled = true
    /// Blink to another display every so often. Only does anything when there is
    /// more than one display to blink to.
    var teleportEnabled = false
    /// Seconds until the next hop. Re-jittered after each one, and a `var` so the
    /// selftest can pin it.
    var teleportInSeconds: Double = Rand.double(45...120)
    /// Displays she has blinked to, for the heartbeat and the selftest.
    private(set) var teleportCount = 0
    var palette: CatPalette = .tabby

    /// Top edges of other apps' windows, refreshed by the perch pump. Empty in
    /// headless tests, which is exactly the old desktop-floor behaviour.
    var platforms: [WindowPlatform] = []

    /// Owner name of the frontmost app. A soft preference when she picks a
    /// ledge: jumping onto the window you are working in reads as attention,
    /// jumping onto a random one reads as a bug.
    var preferredPlatformOwner: String?

    /// Set by the controller while a bubble is up. Idle root-moving behaviour is
    /// suppressed during a sentence (DESIGN.md §5, rule 4).
    var isTalking = false

    // The rest ladder. All four are jittered so she does not settle on a
    // metronome, and all four are `var`s so the selftest can run the whole
    // ladder — perch, loaf, sit, sleep, wake — in seconds instead of minutes.
    /// Idle seconds before she sits down: the "before sleep" half of the loaf
    /// and the sit.
    var sitAfterSeconds: Double = Rand.double(45...80)
    /// Seconds of stillness on a perch before she tucks her paws under.
    var loafAfterSeconds: Double = Rand.double(8...16)
    /// How long the loaf lasts before she gets up again. Re-jittered per perch,
    /// so a long stay is a few loafs rather than one long freeze: a cat that has
    /// settled is still a cat that eventually moves.
    var loafHoldSeconds: Double = Rand.double(20...45)
    /// Idle seconds before she stretches and yawns. Once per idle period: this
    /// is "after a long idle", not a tic.
    var stretchAfterSeconds: Double = Rand.double(35...70)
    /// Idle seconds before she is asleep. The same clock `isAsleep` uses.
    var sleepAfterSeconds: Double = 150

    // Output the view consumes
    private(set) var origin: CGPoint
    private(set) var pose = CatPose.neutral
    private(set) var velocity = CGVector.zero
    private(set) var isDragging = false

    /// Where her window's bottom-left corner goes, in screen coordinates.
    ///
    /// `origin` is the physics anchor — the line her feet are on — and the
    /// window hangs `CatGeometry.groundInset` below it, because the stage has to
    /// hold the parts that swing under her feet. Everything that maps a design
    /// point to the screen goes through here, so the drawing, the gaze and the
    /// bubble all agree on where she actually is.
    var windowOrigin: CGPoint {
        let fit = CatGeometry.fit(in: size)
        return CGPoint(x: origin.x, y: origin.y - CatGeometry.groundInset * fit.scale)
    }

    /// Keep the sliver-on-screen rule after an external change to her size or
    /// to the display layout.
    func keepOnScreen() {
        let region = desktop.region(containing: origin)
        origin.x = min(max(origin.x, region.minX - 30), region.maxX - size.width + 30)
        origin.y = min(max(origin.y, region.minY), region.maxY - size.height * 0.4)
    }

    /// Change her size, keeping her feet on the same spot and her middle where
    /// it was. The behaviour geometry follows, so every distance she reasons
    /// about — jump reach, whether a ledge fits her, wander bounds — is
    /// immediately in the new scale.
    func resize(to newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        origin.x += (size.width - newSize.width) / 2
        size = newSize
        keepOnScreen()
    }

    /// True while she is off the ground and not being held. The frame pump uses
    /// this to stay at display rate through a throw instead of dropping to the
    /// idle tier mid-flight.
    private(set) var isAirborne = false
    /// True while the landing squash is still animating.
    private(set) var isSettling = false
    /// True during the crouch that precedes a jump. The frame pump keeps 30 fps
    /// for it so the gather is visible rather than one frame long.
    private(set) var isCrouching = false
    /// Jumps taken, for the heartbeat and the selftest.
    private(set) var jumpCount = 0
    /// Nothing has interacted with her for long enough that she has gone to
    /// sleep. The same threshold the `sleepy` mood uses.
    var isAsleep: Bool { idleSeconds > sleepAfterSeconds }

    /// The resting shape she is easing into. `stand` unless something else is
    /// true: perched and still means a loaf, idle for a long time means a sit,
    /// asleep means a lie.
    private(set) var restingShape: CatShape = .stand
    /// The shape she is mostly wearing right now. Standing-shape with the
    /// default weights, so an untouched pet reports `stand`.
    var shape: CatShape { pose.shape.dominant }
    /// True while she is visibly between shapes — the frame pump uses this so a
    /// settle is never drawn at the sleep tier.
    var isChangingShape: Bool { !baseShape.isSettled }
    /// True while the scripted stretch and yawn is playing.
    private(set) var isStretching = false
    /// True while she is settled into a resting shape: sitting, loafing or
    /// lying. Deliberately keyed off the *ladder's* answer rather than the
    /// blended pose, so a stretch laid over a sit is still resting — otherwise
    /// the stretch would be the moment she stood up and wandered off.
    var isResting: Bool {
        switch restingShape {
        case .sit, .loaf, .lie: return !isChangingShape
        case .stand, .stretch: return false
        }
    }
    /// Seconds she has been still on her current perch. The loaf's trigger.
    private(set) var perchSeconds: Double = 0

    /// Impact speed of the most recent landing, consumed by the controller so
    /// she can react to a hard drop. Reset to 0 when read.
    private(set) var pendingLandingImpact: CGFloat = 0

    /// Global cursor position in screen coordinates, pushed in by the view.
    /// `NSEvent.mouseLocation` costs nothing and needs no permission.
    var cursor: CGPoint?

    /// Set true while the pet is hidden or the display is asleep.
    var isPaused = false

    // Physics tuning
    private let gravity: CGFloat = 2100
    private let restitution: CGFloat = 0.42
    private let maxLaunchSpeed: CGFloat = 2600
    /// Horizontal air resistance, as a per-second decay factor. The jump
    /// planner integrates this too, so a leap lands where it was aimed.
    private let airDrag: Double = 0.72
    private let walkSpeed: CGFloat = 46
    /// Long trips get a trot, otherwise crossing a 4K desktop takes a minute.
    private let trotSpeed: CGFloat = 88
    private let trotThreshold: CGFloat = 700

    // Jump tuning. A cat jumps several times its own height, and window tops on
    // a real desktop sit 700–1100 pt above the floor: a pet that can only reach
    // 200 pt never gets on anything.
    private let maxJumpSpeed: CGFloat = 2250
    private let maxJumpRise: CGFloat = 1050
    private let maxJumpDistance: CGFloat = 1100
    /// Long enough to read as a gather, short enough not to feel like a pause.
    private let jumpWindup: Double = 0.16

    // Internal state
    private var time: Double = 0
    private var facing: Double = 1
    private var blinkCountdown: Double = 3
    private var blinkProgress: Double = -1
    private var blinkDoubleUp = false
    private var wanderCountdown: Double = 6
    private var wanderTargetX: CGFloat?
    private var microCountdown: Double = 8
    private var earTwitch: Double = 0
    private var squashKick: Double = 0
    private var dragGrabOffset = CGSize.zero
    private var dragSamples: [(time: Double, point: CGPoint)] = []
    private var lastCursor: CGPoint?
    private var idleSeconds: Double = 0
    private var jumpCountdown: Double = 7
    private var jumpWindupRemaining: Double = 0
    private var pendingJump: CGVector?
    /// The blended shape weights actually drawn: the rest ladder, with the
    /// scripted stretch laid over the top.
    private var baseShape = CatShapeWeights()
    private var wasAsleep = false
    private var stretchTime: Double = 0
    private var stretchFiredThisIdlePeriod = false
    private var lastIdleSeconds: Double = 0
    private var wakeStretchPending = false

    init(origin: CGPoint, size: CGSize, desktop: Desktop = .current()) {
        self.origin = origin
        self.size = size
        self.desktop = desktop
    }

    // MARK: - Input

    /// Something the user did: moved the cursor over her, petted her, picked her
    /// up. Restarts the idle clock, which is what wakes a sleeping cat — and a
    /// cat that has just woken up stretches.
    func noteInteraction() {
        idleSeconds = 0
    }

    func beginDrag(at point: CGPoint) {
        isDragging = true
        dragGrabOffset = CGSize(width: point.x - origin.x, height: point.y - origin.y)
        velocity = .zero
        dragSamples = [(time, point)]
        wanderTargetX = nil
        noteInteraction()
        // The user's hand outranks a gather she had already started.
        jumpWindupRemaining = 0
        pendingJump = nil
        isCrouching = false
    }

    func updateDrag(to point: CGPoint) {
        guard isDragging else { return }
        let region = desktop.region(containing: point)
        let proposed = CGPoint(x: point.x - dragGrabOffset.width, y: point.y - dragGrabOffset.height)
        // Keep at least a sliver on screen while the user is holding Pookie.
        origin = CGPoint(
            x: min(max(proposed.x, region.minX - 30), region.maxX - size.width + 30),
            y: min(max(proposed.y, region.minY - size.height * 0.5), region.maxY - size.height * 0.4)
        )
        dragSamples.append((time, point))
        if dragSamples.count > 10 { dragSamples.removeFirst() }
    }

    func endDrag() {
        guard isDragging else { return }
        isDragging = false

        guard let last = dragSamples.last else { velocity = .zero; return }
        let window = dragSamples.filter { last.time - $0.time <= 0.12 }
        guard let first = window.first, last.time - first.time > 0.004 else {
            velocity = .zero
            dragSamples.removeAll()
            return
        }

        let dt = CGFloat(last.time - first.time)
        var vx = (last.point.x - first.point.x) / dt
        var vy = (last.point.y - first.point.y) / dt
        let speed = hypot(vx, vy)
        if speed > maxLaunchSpeed {
            let scale = maxLaunchSpeed / speed
            vx *= scale
            vy *= scale
        }
        velocity = CGVector(dx: vx, dy: vy)
        dragSamples.removeAll()
        noteInteraction()
    }

    /// Nudge the pet somewhere, used by the CLI/MCP control plane from M3.
    func move(to point: CGPoint, animated: Bool = true) {
        if animated {
            wanderTargetX = point.x
            origin.y = max(origin.y, desktop.region(containing: point).minY)
        } else {
            origin = point
        }
    }

    // MARK: - Simulation

    /// Advances the simulation by `dt`, sub-stepping internally.
    ///
    /// Motion is decoupled from the render rate: the window controller may only
    /// draw 8 times a second while the cat sleeps, but the simulation still
    /// integrates at 60 Hz so gravity, bounces, and the idle clock stay honest.
    func advance(dt: Double) {
        guard !isPaused, dt > 0 else { return }
        var remaining = min(dt, 0.5)
        while remaining > 0 {
            let sub = min(remaining, 1.0 / 60.0)
            stepOnce(sub)
            remaining -= sub
        }
    }

    private func stepOnce(_ dt: Double) {
        time += dt
        idleSeconds += dt

        if !isDragging {
            updateJump(dt)
            integrate(dt)
        } else {
            applyDragDeformation()
        }

        updateTeleport(dt)
        updateRest(dt)
        updatePose(dt)
    }

    // MARK: - Teleporting between displays

    /// A cat on a two-monitor desk that only ever lives on one of them is half a
    /// pet. This is the whole mechanic: wait a jittered minute, then be
    /// somewhere else.
    private func updateTeleport(_ dt: Double) {
        guard teleportEnabled, desktop.visibleFrames.count > 1 else { return }
        // She does not blink out of your hand, out of mid-air, out of a
        // sentence, or out of a nap.
        guard !isDragging, !isAirborne, !isCrouching, !isTalking, !isAsleep else { return }

        teleportInSeconds -= dt
        guard teleportInSeconds <= 0 else { return }
        teleportInSeconds = Rand.double(45...120)
        _ = teleportToRandomScreen()
    }

    /// Blink her onto another display, at a random spot, landing on whatever
    /// window top is under her. Returns false when there is nowhere else to go.
    @discardableResult
    func teleportToRandomScreen() -> Bool {
        let current = desktop.visibleFrames.firstIndex(of: desktop.region(containing: origin))
        let elsewhere = desktop.visibleFrames.indices.filter { $0 != current }
        guard let index = elsewhere.randomElement() else { return false }

        let region = desktop.visibleFrames[index]
        let minX = region.minX + 10
        let maxX = max(minX, region.maxX - size.width - 10)
        let x = Rand.cg(minX...maxX)
        // Arrive from above, so a window top under her becomes the ground she
        // lands on rather than something she appears in front of.
        origin = CGPoint(x: x, y: surface(at: x + size.width / 2, region: region, from: region.maxY))
        velocity = .zero
        wanderTargetX = nil
        jumpWindupRemaining = 0
        pendingJump = nil
        isCrouching = false
        perchSeconds = 0
        facing = Rand.bool() ? 1 : -1
        // A landing squash is what sells the arrival as a landing rather than a
        // redraw.
        squashKick = 0.55
        teleportCount += 1
        return true
    }

    // MARK: - Resting shapes and the stretch

    /// How long a settle takes, and how long standing up takes. A cat lowers
    /// herself over about a second and gets up in a hurry.
    private let settleSeconds: Double = 0.9
    private let standUpSeconds: Double = 0.35
    /// Long enough to read the bow, the yawn and the ears going back.
    private let stretchSeconds: Double = 1.7

    /// The rest ladder, plus the two things that interrupt it: waking up, and a
    /// long idle. Runs before `updatePose`, so the pose it writes is the one the
    /// renderer and the gaze use this frame.
    private func updateRest(_ dt: Double) {
        let asleep = isAsleep

        // Waking is an edge, and it is the one moment a cat always stretches.
        // Queued rather than started here: she may be mid-air when the edge
        // happens (you picked her up), and a stretch is a thing you do standing
        // on something.
        if wasAsleep && !asleep { wakeStretchPending = true }
        wasAsleep = asleep

        // The idle clock only ever moves backwards when something interacted
        // with her, which is exactly when a new idle period begins.
        if idleSeconds < lastIdleSeconds { stretchFiredThisIdlePeriod = false }
        lastIdleSeconds = idleSeconds

        updatePerchSeconds(dt)
        updateStretch(dt)
        updateShape(dt)
    }

    /// Time spent still on a perch. Walking, being carried, or being airborne
    /// all reset it, so the loaf really is "she settled here" — and a fresh
    /// perch gets a fresh loaf length.
    private func updatePerchSeconds(_ dt: Double) {
        let still = !isDragging && !isAirborne && !isCrouching
            && wanderTargetX == nil && !isTalking
        if still, supportPlatform() != nil {
            if perchSeconds == 0 {
                // A fresh landing. The wander clock is pushed out so she gets
                // to settle at all: otherwise it fires a few seconds in and the
                // loaf (8–16 s) never wins the race, and the best thing she
                // does would almost never be seen.
                wanderCountdown = max(wanderCountdown, Rand.double(12...30))
                loafHoldSeconds = Rand.double(20...45)
            }
            perchSeconds += dt
        } else if perchSeconds > 0 {
            perchSeconds = 0
        }
    }

    /// Whether a stretch could start right now. Deliberately strict: not while
    /// she is being held, in the air, talking, or asleep.
    var canStretch: Bool {
        !isDragging && !isAirborne && !isCrouching && !isTalking && !isAsleep
            && wanderTargetX == nil
    }

    private func updateStretch(_ dt: Double) {
        if isStretching {
            stretchTime += dt
            if stretchTime >= stretchSeconds {
                isStretching = false
                stretchTime = 0
            }
            return
        }

        if wakeStretchPending, canStretch {
            wakeStretchPending = false
            // The waking stretch counts as this idle period's stretch: one bow
            // per period, whether it came from waking up or from sitting still.
            stretchFiredThisIdlePeriod = true
            beginStretch()
            return
        }

        if !stretchFiredThisIdlePeriod, idleSeconds >= stretchAfterSeconds, canStretch {
            stretchFiredThisIdlePeriod = true
            beginStretch()
        }
    }

    @discardableResult
    func beginStretch() -> Bool {
        guard canStretch else { return false }
        isStretching = true
        stretchTime = 0
        return true
    }

    /// The stretch timeline: snappy into the bow, a hold at the top for the
    /// yawn, and a slower settle back down. Pure, so the selftest can check the
    /// shape of it without running the animation.
    static func stretchCurve(_ progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        let rise = 0.28
        let hold = 0.62
        if t < rise {
            let x = t / rise
            return 1 - (1 - x) * (1 - x)
        }
        if t < hold { return 1 }
        let x = (t - hold) / (1 - hold)
        return 1 - x * x * (3 - 2 * x)
    }

    /// Which rest shape everything else implies, highest priority first.
    ///
    /// Movement and being held win: a cat being carried is not a cat lying
    /// down. Then sleep, then the sit that precedes it, then the loaf that
    /// follows a long perch — which, unlike the others, is a bounded episode
    /// rather than a state, so she gets up again on her own.
    private func desiredRestingShape() -> CatShape {
        if isDragging || isAirborne || isCrouching || isTalking { return .stand }
        if wanderTargetX != nil { return .stand }
        if isAsleep { return .lie }
        if idleSeconds >= sitAfterSeconds { return .sit }
        if perchSeconds >= loafAfterSeconds, perchSeconds < loafAfterSeconds + loafHoldSeconds {
            return .loaf
        }
        return .stand
    }

    private func updateShape(_ dt: Double) {
        let desired = desiredRestingShape()
        restingShape = desired
        let duration = desired == .stand ? standUpSeconds : settleSeconds
        baseShape.approach(desired, by: dt / duration)

        // The scripted stretch lays over the resting shape rather than
        // replacing it, so waking up out of a lie uncurls instead of cutting.
        var weights = baseShape
        if isStretching {
            let amount = Self.stretchCurve(stretchTime / stretchSeconds)
            weights = .lerp(baseShape, .only(.stretch), amount)
        }
        pose.shape = weights
    }

    // MARK: - Jumping onto things

    /// A ballistic hop to a window top: the launch velocity and which way to face.
    struct JumpPlan {
        var velocity: CGVector
        var facing: Double
        /// Where she intends to land, for logging and tests.
        var target: CGPoint
    }

    /// Crouch, then launch. Called every sub-step.
    private func updateJump(_ dt: Double) {
        if jumpWindupRemaining > 0 {
            jumpWindupRemaining -= dt
            isCrouching = jumpWindupRemaining > 0
            if jumpWindupRemaining <= 0, let impulse = pendingJump {
                pendingJump = nil
                velocity = impulse
                jumpCount += 1
                squashKick = 0
            }
            return
        }

        guard jumpEnabled, !isTalking, !isPaused else { return }

        jumpCountdown -= dt
        guard jumpCountdown <= 0 else { return }
        // Retry soon if there is nothing to jump to: a window can appear at any
        // moment, and a 20-second wait to notice it feels dead.
        jumpCountdown = requestJump() ? Rand.double(12...32) : Rand.double(3...8)
    }

    /// Plan and begin a jump onto the best window top she can reach, if there is
    /// one. Returns false when she is busy or has nowhere to go.
    @discardableResult
    func requestJump() -> Bool {
        guard jumpEnabled, perchEnabled, !isDragging, !isAirborne, !isTalking else { return false }
        // Asleep cats do not leap.
        guard !isAsleep else { return false }
        guard let plan = planJump() else { return false }

        pendingJump = plan.velocity
        jumpWindupRemaining = jumpWindup
        isCrouching = true
        facing = plan.facing
        wanderTargetX = nil
        return true
    }

    /// The jump planner. Pure: no state changes, so the selftest can ask what
    /// she would do without making her do it.
    ///
    /// A ledge is a candidate only if, after landing, she is **fully visible**:
    /// the whole window has to fit on the screen that owns the ledge, and on the
    /// ledge itself. A window top tucked against the edge of a display, or
    /// narrower than the cat, is skipped rather than jumped at.
    func planJump() -> JumpPlan? {
        guard perchEnabled else { return nil }

        let homeRegion = desktop.region(containing: origin)
        let ground = surface(at: origin.x + size.width / 2, region: homeRegion, from: origin.y)
        // Only from solid ground, not mid-air or mid-wobble.
        guard origin.y <= ground + 0.5 else { return nil }

        var best: (plan: JumpPlan, score: CGFloat)?

        for platform in platforms {
            let ledge = CGPoint(x: platform.rect.midX, y: platform.top)
            let region = desktop.region(containing: ledge)

            // Where she could stand: fully on the ledge, and fully on screen.
            let minX = max(platform.rect.minX, region.minX)
            let maxX = min(platform.rect.maxX - size.width, region.maxX - size.width)
            guard maxX >= minX else { continue }
            // Vertically: under the menu bar, above the floor.
            guard platform.top >= region.minY, platform.top + size.height <= region.maxY else { continue }

            let rise = platform.top - origin.y
            guard rise > 6, rise <= maxJumpRise else { continue }

            let targetX = min(max(origin.x, minX), maxX)
            let dx = targetX - origin.x
            guard abs(dx) <= maxJumpDistance else { continue }

            // Ballistic arc. The exact minimum-energy flight time arrives at the
            // ledge with *zero* vertical speed, which a discrete integrator
            // never quite reaches: she peaks a few points short and falls back
            // down. So aim 18% short of that, which puts the apex above the
            // ledge and lands her on the way down.
            let flight = max(0.34, 0.82 * Double(sqrt(2 * rise / gravity)))
            let vy = rise / CGFloat(flight) + 0.5 * gravity * CGFloat(flight)
            // Horizontal travel is damped by the same air resistance the physics
            // applies, so integrate the decay rather than assuming constant
            // speed: `∫ 0.72^t dt` over the flight. Without this she lands about
            // a fifth of the way short of every target.
            let dragIntegral = (1 - pow(airDrag, flight)) / -log(airDrag)
            let vx = dx / CGFloat(dragIntegral)
            guard vy <= maxJumpSpeed, hypot(vx, vy) <= maxLaunchSpeed else { continue }

            // The arc has to fit under the ceiling, or the clamp cuts it short.
            let apex = origin.y + vy * vy / (2 * gravity)
            guard apex <= region.maxY - size.height + 2 else { continue }

            var score = abs(dx) + rise * 0.35
            if let preferred = preferredPlatformOwner, platform.ownerName == preferred {
                score -= 260
            }
            if best == nil || score < best!.score {
                let heading: Double
                if dx > 2 { heading = 1 } else if dx < -2 { heading = -1 } else { heading = facing }
                best = (
                    JumpPlan(
                        velocity: CGVector(dx: vx, dy: vy),
                        facing: heading,
                        target: CGPoint(x: targetX, y: platform.top)
                    ),
                    score
                )
            }
        }
        return best?.plan
    }

    private func integrate(_ dt: Double) {
        let region = desktop.region(containing: origin)
        var v = velocity
        let previousY = origin.y

        v.dy -= gravity * CGFloat(dt)
        // Air resistance. Without this, a flung cat keeps its release velocity
        // for the whole flight and ricochets across every display before it
        // stops. Halves over roughly two seconds.
        v.dx *= CGFloat(pow(airDrag, dt))
        origin.x += v.dx * CGFloat(dt)
        origin.y += v.dy * CGFloat(dt)

        // Walls.
        let maxX = region.maxX - size.width
        if origin.x < region.minX {
            origin.x = region.minX
            v.dx = abs(v.dx) * 0.5
        } else if origin.x > maxX {
            origin.x = maxX
            v.dx = -abs(v.dx) * 0.5
        }

        // Floor, which is the desktop *or* the top edge of a window she is
        // above. Resolved after the horizontal move so walking off the end of a
        // window drops her, and against the previous altitude so a fast fall
        // lands on the window top instead of tunnelling through it.
        let floor = surface(at: origin.x + size.width / 2, region: region, from: previousY)
        if origin.y <= floor {
            origin.y = floor
            if v.dy < -60 {
                v.dy = -v.dy * restitution
                v.dx *= 0.84
                squashKick = min(1.0, Double(abs(v.dy) / 900))
                pendingLandingImpact = max(pendingLandingImpact, abs(v.dy))
            } else {
                v.dy = 0
                // Framerate-independent ground friction.
                v.dx *= CGFloat(pow(0.045, dt))
            }
        }

        // Ceiling, never below the floor she is standing on.
        let ceiling = max(floor, region.maxY - size.height)
        if origin.y > ceiling {
            origin.y = ceiling
            v.dy = min(v.dy, 0)
        }

        velocity = v
        // "Grounded" is about altitude only. Testing horizontal velocity here
        // would cancel every walk the moment it started.
        wander(dt, grounded: origin.y <= floor + 0.5)
    }

    /// The highest thing the cat can stand on at `x` right now.
    ///
    /// Platforms are one-way: a window top only counts if she is already at or
    /// above it. That is what lets her walk on a window without being launched
    /// onto the top of every window she walks in front of.
    func surface(at x: CGFloat, region: CGRect, from y: CGFloat) -> CGFloat {
        var floor = region.minY
        guard perchEnabled else { return floor }

        // Standing on it means fitting under the ceiling; a window whose top is
        // above the usable area is not a perch, it is a wall.
        let highestUsable = region.maxY - size.height
        let reach = y + 2

        for platform in platforms where platform.top <= reach && platform.top <= highestUsable {
            guard platform.spans(x) else { continue }
            floor = max(floor, platform.top)
        }
        return floor
    }

    /// The window she is standing on, if any.
    func supportPlatform() -> WindowPlatform? {
        let region = desktop.region(containing: origin)
        let x = origin.x + size.width / 2
        return platforms.first { platform in
            platform.spans(x)
                && abs(platform.top - origin.y) < 1.5
                && platform.top <= region.maxY - size.height
        }
    }

    /// Move with a window the cat is perched on, so a window being dragged
    /// across the desktop carries her instead of sliding out from under her.
    /// Velocity is untouched: she is being carried, not thrown.
    func ride(dx: CGFloat, dy: CGFloat) {
        guard dx != 0 || dy != 0 else { return }
        origin.x += dx
        origin.y += dy
        // Same sliver-on-screen rule as a drag, so riding a window off the edge
        // of a display cannot strand her somewhere unreachable.
        let region = desktop.region(containing: origin)
        origin.x = min(max(origin.x, region.minX - 30), region.maxX - size.width + 30)
    }

    /// Consume the last landing impact (pt/s), for reaction lines.
    func takeLandingImpact() -> CGFloat {
        defer { pendingLandingImpact = 0 }
        return pendingLandingImpact
    }

    /// Pookie ambles to a new spot every so often. Cheap, and it is the thing
    /// that stops a desktop pet from feeling like a sticker.
    private func wander(_ dt: Double, grounded: Bool) {
        guard wanderEnabled, grounded, !isDragging else {
            if !grounded { wanderTargetX = nil }
            return
        }

        if let target = wanderTargetX {
            let delta = target - origin.x
            if abs(delta) < 8 {
                wanderTargetX = nil
                wanderCountdown = Rand.double(7...18)
            } else {
                let speed = abs(delta) > trotThreshold ? trotSpeed : walkSpeed
                velocity.dx = (delta > 0 ? 1 : -1) * min(speed, abs(delta) * 1.6)
                facing = delta > 0 ? 1 : -1
            }
            return
        }

        // Do not *start* anything while she is settled into a rest: a cat that
        // has lain down does not get up on a timer. The loaf ends by its own
        // clock (see `desiredRestingShape`), the sit is the run-up to sleep, and
        // a sleeping cat must not stand up and wander off mid-nap.
        guard !isResting else { return }

        wanderCountdown -= dt
        guard wanderCountdown <= 0 else { return }

        // Standing on a window, most wanders stay on it. A cat that walks off
        // the ledge she just landed on never reads as having settled there — but
        // she still leaves sometimes, which is how she gets down.
        if let perch = supportPlatform(), Rand.bool(0.8) {
            let ledgeMin = perch.rect.minX + 8
            let ledgeMax = perch.rect.maxX - size.width - 8
            if ledgeMax > ledgeMin {
                wanderTargetX = Rand.cg(ledgeMin...ledgeMax)
                return
            }
        }

        // Prefer the screen the pointer is on, so Pookie drifts back to wherever
        // you are actually working instead of stranding itself on the monitor
        // it was last flung at.
        var region = desktop.region(containing: origin)
        if let cursor, Rand.bool(0.65) {
            let cursorRegion = desktop.region(containing: cursor)
            if cursorRegion != region {
                region = cursorRegion
            }
        }

        let minX = region.minX + 10
        let maxX = region.maxX - size.width - 10
        guard maxX > minX else { return }

        var candidate = Rand.cg(minX...maxX)
        if abs(candidate - origin.x) < 140 {
            candidate = origin.x < region.midX ? maxX : minX
        }
        wanderTargetX = candidate
    }

    private func applyDragDeformation() {
        // Stretch along the direction of travel while being carried.
        guard dragSamples.count >= 2 else { return }
        let last = dragSamples[dragSamples.count - 1]
        let previous = dragSamples[dragSamples.count - 2]
        let dt = max(0.001, last.time - previous.time)
        let vx = CGFloat((last.point.x - previous.point.x) / dt)
        let vy = CGFloat((last.point.y - previous.point.y) / dt)
        let speed = min(1.0, hypot(vx, vy) / 1800)
        let limits = CatPose.RenderLimits.self
        pose.stretch = 1 + speed * (limits.maxStretch - 1)
        pose.squash = 1 - speed * (1 - limits.minSquash)
        pose.tilt = Double(max(-limits.tilt, min(limits.tilt, vx / 4200)))
        if abs(vx) > 60 { facing = vx > 0 ? 1 : -1 }
    }

    // MARK: - Pose

    private func updatePose(_ dt: Double) {
        let region = desktop.region(containing: origin)
        let ground = surface(at: origin.x + size.width / 2, region: region, from: origin.y)
        let airborne = !isDragging && origin.y > ground + 0.5
        let sleepy = isAsleep

        isAirborne = airborne
        isSettling = squashKick > 0.02

        // Breathing: slower and deeper when asleep.
        let breatheRate = sleepy ? 0.7 : 1.5
        pose.breathe = sin(time * breatheRate)

        // Tail.
        let tailRate: Double
        switch pose.mood {
        case .happy: tailRate = 3.6
        case .dragged, .alarmed: tailRate = 4.6
        case .sleepy: tailRate = 0.5
        default: tailRate = 1.3
        }
        pose.tailPhase = time * tailRate

        // Ear twitch, occasional.
        earTwitch *= CGFloat(pow(0.02, dt))
        pose.earTwitch = Double(earTwitch)

        // Blink scheduling.
        updateBlink(dt)

        // Deformation: squash kick decays, airborne stretch overrides. The
        // magnitudes stay inside `CatPose.RenderLimits`, which is the envelope
        // the renderer's stage is sized for — asking for more would just be
        // silently clamped, and then this code would be lying about the pose.
        squashKick = max(0, min(1, squashKick * pow(0.015, dt)))
        if isDragging {
            // applyDragDeformation already set these.
        } else if airborne {
            let stretch = min(
                CatPose.RenderLimits.maxSquash - 1,
                Double(abs(velocity.dy)) / 2600
            )
            pose.stretch = 1 - stretch * 0.6
            pose.squash = 1 + stretch
            pose.hopOffset = 0
        } else if isCrouching {
            // Gather before the leap: low and wide, so the launch reads.
            pose.stretch = CatPose.RenderLimits.maxStretch
            pose.squash = CatPose.RenderLimits.minSquash
            pose.tilt = 0
        } else {
            pose.stretch = 1 + squashKick * (CatPose.RenderLimits.maxStretch - 1)
            pose.squash = 1 - squashKick * (1 - CatPose.RenderLimits.minSquash)
            pose.tilt = 0
        }

        pose.facing = facing

        // Walking bob.
        let walking = wanderTargetX != nil && origin.y <= ground + 0.5
        // Walking bob. Clamped to the render envelope: a bigger hop lifts the
        // ears past the top of the stage and the renderer would have to clip
        // them (which is exactly the bug this limit exists to prevent).
        if walking {
            pose.hopOffset = abs(sin(time * 9)) * Double(CatPose.RenderLimits.hop)
            pose.tilt = sin(time * 9) * 0.03
        } else if !airborne && !isDragging {
            pose.hopOffset = 0
        }

        updateGaze(dt)

        // Micro-behaviours: a small hop, an ear flick, a glance around.
        microCountdown -= dt
        if microCountdown <= 0 {
            microCountdown = Rand.double(6...16)
            if !isDragging && !airborne {
                earTwitch = Rand.cg(0.10...0.26) * (Rand.bool() ? 1 : -1)
            }
        }

        // Mouth is reserved for M2's speech; idle cats keep it shut.
        pose.mouthOpen *= pow(0.02, dt)

        pose.mood = resolveMood(sleepy: sleepy, airborne: airborne, walking: walking)
        pose.blush = pose.mood == .happy ? min(1, pose.blush + dt * 2) : max(0, pose.blush - dt * 3)
    }

    private func updateBlink(_ dt: Double) {
        if blinkProgress >= 0 {
            blinkProgress += dt
            let duration = 0.14
            let t = blinkProgress / duration
            if t < 0.5 {
                pose.blink = 1 - t * 2
            } else if t < 1 {
                pose.blink = (t - 0.5) * 2
            } else if blinkDoubleUp {
                blinkDoubleUp = false
                blinkProgress = 0
            } else {
                pose.blink = 1
                blinkProgress = -1
                blinkCountdown = Rand.double(2.5...6.5)
            }
            return
        }

        blinkCountdown -= dt
        guard blinkCountdown <= 0 else { return }
        blinkProgress = 0
        blinkDoubleUp = Rand.bool(0.18)
    }

    /// Where a design-space point sits on screen, through the same fit the
    /// renderer uses. The gaze and the "is the cursor near her face?" test used
    /// to approximate this with fractions of the window, which drifted as soon
    /// as the stage changed size.
    private func screenPoint(designX: CGFloat, designY: CGFloat) -> CGPoint {
        let fit = CatGeometry.fit(in: size)
        let local = fit.viewPoint(x: designX, y: designY)
        let frame = windowOrigin
        return CGPoint(x: frame.x + local.x, y: frame.y + local.y)
    }

    private func updateGaze(_ dt: Double) {
        guard followCursor, let cursor else {
            pose.gazeX += (0 - pose.gazeX) * min(1, dt * 4)
            pose.gazeY += (0 - pose.gazeY) * min(1, dt * 4)
            return
        }

        if let last = lastCursor, hypot(cursor.x - last.x, cursor.y - last.y) > 1.5 {
            noteInteraction()
        }
        lastCursor = cursor

        let headScreen = screenPoint(designX: 50, designY: CatAnatomy.blend(pose.shape).eyeY)
        let dx = cursor.x - headScreen.x
        let dy = cursor.y - headScreen.y
        let distance = max(1, hypot(dx, dy))
        let reach = min(1.0, Double(distance / 240))
        let targetX = Double(dx / distance) * reach
        let targetY = Double(dy / distance) * reach

        let follow = min(1, dt * 9)
        pose.gazeX += (targetX - pose.gazeX) * follow
        pose.gazeY += (targetY - pose.gazeY) * follow

        // Turn to face the cursor once it is clearly off to one side.
        if !isDragging, wanderTargetX == nil, abs(dx) > 110 {
            facing = dx > 0 ? 1 : -1
        }
    }

    private func resolveMood(sleepy: Bool, airborne: Bool, walking: Bool) -> CatMood {
        if isDragging { return .dragged }
        if airborne && abs(velocity.dy) > 700 { return .alarmed }
        if sleepy { return .sleepy }
        if let cursor, followCursor {
            let headScreen = screenPoint(designX: 50, designY: CatAnatomy.blend(pose.shape).headCenter.y)
            if hypot(cursor.x - headScreen.x, cursor.y - headScreen.y) < 90 { return .curious }
        }
        if walking { return .walking }
        return .idle
    }

    var facingDirection: Double { facing }
}
