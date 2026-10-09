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
    /// How often she blinks, before the jitter. Set from the settings; the
    /// jitter is what stops five pets blinking in unison.
    var teleportCadence: TeleportCadence = .normal
    /// Seconds until the next hop. Re-jittered after each one, and a `var` so the
    /// selftest can pin it.
    var teleportInSeconds: Double = TeleportCadence.normal.seconds * Rand.double(0.65...1.35)
    /// Displays she has blinked to, for the heartbeat and the selftest.
    private(set) var teleportCount = 0

    /// What kind of animal she is. Written into the pose each frame, so the
    /// renderer, the envelope test and the gaze anchor all read one value.
    var species: PetSpecies = .cat

    /// Markings over the coat, written into the pose like the species.
    var pattern: PookiePattern = .plain

    /// Where the other pets are, pushed in by the cohort. Used for two things:
    /// not standing inside each other, and chasing each other around.
    var companions: [CGPoint] = []
    /// Seconds left in a play bout. Started by the cohort when two pets notice
    /// each other; a playing cat chases her playmate and wears the happy face.
    private(set) var playSeconds: Double = 0
    var isPlaying: Bool { playSeconds > 0 }
    /// Bouts played, for the heartbeat and the selftest.
    private(set) var playCount = 0
    private var playRetarget: Double = 0

    /// Seconds left in a scuffle: the close-quarters version of playing. Two
    /// animals who are already next to each other bat at each other instead of
    /// chasing, which is what "a little fight" looks like.
    private(set) var scuffleSeconds: Double = 0
    var isScuffling: Bool { scuffleSeconds > 0 }
    /// Scraps had, for the heartbeat and the selftest.
    private(set) var scuffleCount = 0
    /// Seconds left of a burst of zoomies: the sudden dash across the desk that
    /// every cat does at eleven at night.
    private(set) var zoomiesSeconds: Double = 0
    private var zoomiesCountdown: Double = Rand.double(45...150)
    /// Grooming: a paw up to the face, washing behind it.
    private(set) var groomSeconds: Double = 0
    private var groomCountdown: Double = Rand.double(60...180)
    private(set) var groomCount = 0
    /// A tail-chase: she turns on the spot after her own tail.
    private(set) var spinSeconds: Double = 0
    private var spinCountdown: Double = Rand.double(90...260)
    private(set) var spinCount = 0
    /// Peering over the edge of whatever she is standing on.
    private(set) var peekSeconds: Double = 0
    /// How likely a peer is, per frame, once she is settled on something. A `var`
    /// so a test can pin it: this is a random behaviour, and a random behaviour
    /// that can interrupt a loaf makes the loaf untestable.
    var peekChance: Double = 0.0006
    /// A stretch up, after a nap.
    private(set) var reachSeconds: Double = 0

    /// How long the current brawl was scheduled to run, so the punch/kick
    /// alternation has a clock that cannot drift away from the pose.
    private var scuffleLength: Double = 2
    /// Seconds left of a flinch: the face and the stagger after being hit.
    private(set) var hurtSeconds: Double = 0
    /// Which way the blow pushed her, so the head snaps away from it.
    private var hurtDirection: CGFloat = 1
    /// Set when this pookie's swing has landed, for the cohort to hand to the
    /// other one. A punch that nobody feels is a dance, which is exactly what
    /// this looked like.
    private var pendingHit = false
    /// Counts, for the heartbeat.
    private(set) var hitsLanded = 0
    private(set) var hitsTaken = 0
    /// Set when she wants to yelp about it.
    private var pendingYelp = false

    /// Consume "my swing landed".
    func takePendingHit() -> Bool {
        defer { pendingHit = false }
        return pendingHit
    }

    /// Consume "she was hit, say something".
    func takeYelp() -> Bool {
        defer { pendingYelp = false }
        return pendingYelp
    }

    /// Take a punch: a squint, a yelp, and a stagger away from whoever threw it.
    @discardableResult
    func reactToHit(fromX: CGFloat) -> Bool {
        guard !isDragging else { return false }
        hurtSeconds = 0.42
        hurtDirection = origin.x >= fromX ? 1 : -1
        hitsTaken += 1
        pendingYelp = true
        return true
    }

    /// Seconds left of a sneeze, and the little hop and head-shake that go with
    /// it.
    private(set) var sneezeSeconds: Double = 0
    private var sneezeCountdown: Double = Rand.double(90...260)
    /// Counts, for the heartbeat.
    private(set) var zoomiesCount = 0
    private(set) var sneezeCount = 0

    /// How long a rival has been within reach. A brawl is what happens to company
    /// that *stays* close: the human's rule is three seconds, and one frame of
    /// passing each other is not a fight.
    private(set) var nearSeconds: Double = 0
    /// Close enough to have a go at each other, before the three-second clock.
    var brawlRange: CGFloat { personalSpace * 1.35 }
    /// How long company has to stay close before somebody throws a paw.
    var brawlAfterSeconds: Double = 3
    var isBrawlReady: Bool { nearSeconds >= brawlAfterSeconds }
    /// Close enough to be touching. Contact starts a scrap on the spot: three
    /// seconds of *nearness* is for pookies sitting near each other, not for two
    /// who have just walked into each other.
    var isInContact: Bool { nearSeconds > 0 && nearDistance < personalSpace * 0.85 }
    private var nearDistance: CGFloat = .greatestFiniteMagnitude

    /// A scrap is allowed in more situations than a chase: the whole point is
    /// that it happens between neighbours, including two who were already
    /// chasing each other a moment ago.
    var canScuffle: Bool {
        // Deliberately not gated on `wanderEnabled`: that switch is about walking
        // off on her own, and two pookies who end up sitting next to each other
        // will have a go at each other whether or not wandering is allowed.
        !isDragging && !isAirborne && !isCrouching && !isTalking
            && !isAsleep && !isScuffling && !isTeleporting
    }

    /// Start (or extend) a scrap. Returns false when she is in no state for one.
    @discardableResult
    func startScuffle(_ seconds: Double) -> Bool {
        guard canScuffle else { return false }
        if scuffleSeconds <= 0 {
            scuffleCount += 1
            // The clock restarts, so one brawl is not instantly followed by the
            // next the moment this one ends.
            nearSeconds = 0
        }
        scuffleSeconds = max(scuffleSeconds, seconds)
        scuffleLength = max(scuffleLength, scuffleSeconds)
        // The chase, if there was one, is over: this is the contact version.
        playSeconds = 0
        wanderTargetX = nil
        return true
    }

    /// The flinch, ticked down with everything else.
    private func updateHurt(_ dt: Double) {
        guard hurtSeconds > 0 else { return }
        hurtSeconds -= dt
    }

    /// The holds a producer asked for: an emote, and a facing.
    private func updateHolds(_ dt: Double) {
        if emoteSeconds > 0 {
            emoteSeconds -= dt
            if emoteSeconds <= 0 {
                emoteMood = nil
                emoteBlush = false
            }
        }
        if facingHold > 0 {
            facingHold -= dt
            if facingHold <= 0 {
                forcedFacing = nil
            } else if let forcedFacing {
                // Held, not set once: the cursor-following logic would otherwise take
                // the facing straight back.
                facing = forcedFacing
            }
        }
    }

    /// The brawl, and the clock that decides when one starts.
    ///
    /// Close company used to trigger a scrap on the frame it was detected, which
    /// meant two animals wandering past each other never quite managed one. Now
    /// the proximity has to *last*: three seconds of being within reach and
    /// somebody throws a paw.
    private func updateScuffle(_ dt: Double) {
        updateNearbyClock(dt)

        guard scuffleSeconds > 0 else { return }
        scuffleSeconds -= dt
        guard scuffleSeconds > 0 else { return }

        guard let rival = nearestCompanion() else { return }
        let mine = origin.x + size.width / 2
        let theirs = rival.x + size.width / 2
        facing = theirs >= mine ? 1 : -1

        // Close in until they are actually touching. A brawl at arm's length is
        // two animals dancing near each other, which is what the human saw.
        let gap = theirs - mine
        let touching = personalSpace * 0.55
        if abs(gap) > touching {
            origin.x += (gap > 0 ? 1 : -1) * min(abs(gap) * CGFloat(dt) * 2.2, 2.4)
        }
        // The swing lands at the top of the arc, and the *other* one feels it.
        // The same phase the pose uses for the punch, read here so the blow and
        // the flinch cannot drift apart.
        let swing = sin(scuffleSeconds * 6.5)
        if abs(swing) > 0.9, abs(gap) < personalSpace * 0.95 {
            pendingHit = true
            hitsLanded += 1
        }
    }

    /// Zoomies, sneezes, and the head-bump: the small unprompted things.
    private func updateSmallBehaviours(_ dt: Double) {
        guard !isPaused, !isDragging, !isTalking else { return }

        if zoomiesSeconds > 0 {
            zoomiesSeconds -= dt
            if zoomiesSeconds <= 0 { speedBoost = 1 }
            // A dash, not a wander: the target is far and the speed is a sprint.
            if let region = desktop.visibleFrames.first(where: { $0.contains(origin) }) {
                wanderTargetX = Rand.cg(region.minX + 20...max(region.minX + 21, region.maxX - size.width - 20))
            }
            return
        }

        if sneezeSeconds > 0 { sneezeSeconds -= dt }
        if groomSeconds > 0 { groomSeconds -= dt }
        if spinSeconds > 0 { spinSeconds -= dt }
        if peekSeconds > 0 { peekSeconds -= dt }
        if reachSeconds > 0 { reachSeconds -= dt }

        guard !isAirborne, !isAsleep, !isCrouching, !isScuffling else { return }

        zoomiesCountdown -= dt
        if zoomiesCountdown <= 0 {
            zoomiesCountdown = Rand.double(60...200)
            // Only from a standstill: a cat does not interrupt a nap to do this.
            if canStartUnprompted {
                zoomiesSeconds = Rand.double(0.9...1.8)
                zoomiesCount += 1
                speedBoost = 2.1
            }
        }

        sneezeCountdown -= dt
        if sneezeCountdown <= 0 {
            sneezeCountdown = Rand.double(120...300)
            sneeze()
        }

        // Grooming: while awake and not doing anything else, wash.
        groomCountdown -= dt
        if groomCountdown <= 0 {
            groomCountdown = Rand.double(70...200)
            if wanderTargetX == nil, !isScuffling, !isPlaying, stateProfile?.wanders ?? true {
                groom()
            }
        }

        // A tail-chase: the one thing a cat does purely for its own amusement.
        spinCountdown -= dt
        if spinCountdown <= 0 {
            spinCountdown = Rand.double(120...320)
            if canStartUnprompted {
                startTailChase()
            }
        }

        // Peering over the edge of a perch, now and then, when nothing else is
        // happening.
        // Rare, and only once she has settled: a peering pookie should be a
        // surprise, not the pose she spends the afternoon in.
        // Not while she is already settled into a rest: a peer is a thing she does
        // *instead of* loafing, not something that interrupts a loaf.
        if supportPlatform() != nil, wanderTargetX == nil, !isScuffling, !isPlaying,
           !isResting, peekSeconds <= 0, idleSeconds > loafAfterSeconds, Rand.bool(peekChance) {
            peekSeconds = Rand.double(1.6...3.0)
        }
    }

    /// Wash a paw, on demand — which is also how the selftest drives it without
    /// waiting two minutes for the mood to strike.
    @discardableResult
    func groom() -> Bool {
        guard !isDragging, !isAirborne, !isAsleep, groomSeconds <= 0 else { return false }
        groomSeconds = Rand.double(1.4...2.6)
        groomCount += 1
        return true
    }

    /// Chase her own tail, on demand.
    @discardableResult
    func startTailChase() -> Bool {
        guard !isDragging, !isAirborne, !isAsleep, spinSeconds <= 0 else { return false }
        spinSeconds = Rand.double(1.0...1.8)
        spinCount += 1
        return true
    }

    /// An emote the pet was told to wear, and how long is left of it.
    ///
    /// An emote is a *held expression*, which is why it is not the same thing as a
    /// mood: moods are derived from what she is doing, and this one is imposed from
    /// outside for a stated time.
    private var emoteMood: CatMood?
    private var emoteSeconds: Double = 0
    private var emoteBlush = false
    /// A forced facing, from the `face` verb.
    private var facingHold: Double = 0
    private var forcedFacing: Double?
    /// A high-level mode, from the `state` verb. Nil means "the usual profile".
    private var stateProfile: IntentMapping.Profile?

    /// Wear an expression for a while. False for an emote this renderer cannot
    /// honestly do.
    @discardableResult
    func applyEmote(_ emote: IntentMapping.Emote, seconds: Double) -> Bool {
        guard emote.isSupported else { return false }
        emoteMood = emote.mood
        emoteBlush = emote.blushes
        emoteSeconds = max(0.1, seconds)
        return true
    }

    /// Hold a facing direction for a while. `nil` means "back to normal".
    func holdFacing(_ direction: Double?, seconds: Double) {
        forcedFacing = direction
        facingHold = max(0, seconds)
        if let direction { facing = direction }
    }

    /// Force a high-level mode, or clear it.
    func applyState(_ profile: IntentMapping.Profile?) {
        stateProfile = profile
        // "Hold still" has to stop a walk already in progress, not only prevent the
        // next one: otherwise a mode that says stay put leaves her mid-stride, with a
        // sleepy mood and a standing shape, which is exactly what the first live check
        // showed.
        if profile?.wanders == false {
            wanderTargetX = nil
            velocity.dx = 0
        }
        if profile?.celebrates == true, canStartUnprompted {
            zoomiesSeconds = 1.4
            zoomiesCount += 1
        }
    }

    /// The mode in force, for the selftest and the state description.
    var currentStateProfile: IntentMapping.Profile? { stateProfile }

    /// Whether an unprompted behaviour that moves her may start at all. A mode that
    /// says "hold still" means hold still.
    private var canStartUnprompted: Bool {
        guard stateProfile?.wanders ?? true else { return false }
        return !isResting && !isPlaying && !isScuffling && !isTeleporting && wanderTargetX == nil
    }

    /// A stretch up after a nap: the shape, held for a moment.
    private func noteWaking() {
        reachSeconds = Rand.double(1.2...2.2)
    }

    /// A sneeze: a hop, a head shake and one small noise.
    @discardableResult
    func sneeze() -> Bool {
        guard !isDragging, !isAirborne, !isAsleep, sneezeSeconds <= 0 else { return false }
        sneezeSeconds = 0.45
        sneezeCount += 1
        pendingSneezeLine = true
        return true
    }

    /// Count how long anybody has been within reach, and forget it the moment
    /// they are not.
    private func updateNearbyClock(_ dt: Double) {
        guard !isDragging, !isAirborne, !isAsleep, !isTalking else {
            nearSeconds = 0
            return
        }
        let mine = origin.x + size.width / 2
        var nearest = CGFloat.greatestFiniteMagnitude
        for companion in companions where abs(origin.y - companion.y) < size.height * 0.6 {
            nearest = min(nearest, abs(companion.x + size.width / 2 - mine))
        }
        nearDistance = nearest
        nearSeconds = nearest < brawlRange ? nearSeconds + dt : 0
    }

    /// Every pet who is in a state to notice another one. The cohort picks its
    /// play pairs from this.
    ///
    /// `wanderEnabled` is in here on purpose: it is the desk's "no unprompted
    /// walking" switch, and a chase across the screen is exactly that.
    var canPlay: Bool {
        wanderEnabled && !isDragging && !isAirborne && !isCrouching && !isTalking
            && !isAsleep && !isPlaying && !isTeleporting
    }

    /// How close another cat may get before she steps aside. Two cats converging
    /// on the same pixel read as one buggy cat, not as two pets.
    var personalSpace: CGFloat { size.width * 0.9 }

    /// Start (or extend) a play bout. Returns false when she is busy.
    @discardableResult
    func startPlay(_ seconds: Double) -> Bool {
        guard canPlay else { return false }
        if playSeconds <= 0 { playCount += 1 }
        playSeconds = max(playSeconds, seconds)
        playRetarget = 0
        return true
    }

    /// Top edges of other apps' windows, refreshed by the perch pump. Empty in
    /// headless tests, which is exactly the old desktop-floor behaviour.
    var platforms: [WindowPlatform] = []

    /// Owner name of the frontmost app. A soft preference when she picks a
    /// ledge: jumping onto the window you are working in reads as attention,
    /// jumping onto a random one reads as a bug.
    var preferredPlatformOwner: String?

    /// The display she was last resolved to. Kept so a pookie in the seam gap
    /// between two monitors stays on the one she is crossing towards.
    private var lastRegion: CGRect?

    /// How far along a ledge she will aim from directly above her launch point,
    /// as a fraction of the room available. Zero makes a jump deterministic,
    /// which is what the landing-accuracy test pins it to; the default spreads
    /// landings out so every jump from one spot does not end in the same place.
    var jumpLandingSpread: CGFloat = 0.45

    /// Set when a sneeze wants to say something, read and cleared by the shell.
    private var pendingSneezeLine = false

    /// Consume the "she just sneezed" flag, for the line that goes with it.
    func takeSneezeLine() -> Bool {
        defer { pendingSneezeLine = false }
        return pendingSneezeLine
    }

    /// A multiplier on her walk and trot speeds, used by the zoomies.
    private var speedBoost: Double = 1

    /// Where the jump in progress is heading, once one has been planned.
    private(set) var jumpTarget: CGPoint?

    /// The last few windows she jumped to. Without this she picks the same one
    /// every time, which is the difference between a pet exploring the desk and
    /// a pet stuck on one window.
    private var recentJumpOwners: [String] = []

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
    var isAsleep: Bool { (stateProfile?.forcesSleep ?? false) || idleSeconds > sleepAfterSeconds }

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
        case .sit, .loaf, .lie, .curl, .peek: return !isChangingShape
        case .stand, .stretch, .reachUp: return false
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
        // The user's hand outranks an effect in progress: grab a blinking cat and
        // you get a cat, not a half-vanished one.
        teleportPhase = .none
        teleportProgress = 0
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

        updateHurt(dt)
        updateHolds(dt)
        updateSmallBehaviours(dt)
        updatePlay(dt)
        updateScuffle(dt)
        updateTeleport(dt)
        updateRest(dt)
        updatePose(dt)
    }

    // MARK: - Other pets

    /// Chasing, for the length of a bout: aim at the nearest playmate, often
    /// enough to follow her rather than to run at where she was.
    ///
    /// Deliberately expressed through the existing `wanderTargetX`, so a playing
    /// cat walks with the same locomotion, facing and bob as any other walk; the
    /// only new thing is who picks the target.
    private func updatePlay(_ dt: Double) {
        guard playSeconds > 0 else { return }
        playSeconds -= dt
        guard playSeconds > 0 else {
            wanderTargetX = nil
            return
        }

        playRetarget -= dt
        guard playRetarget <= 0 else { return }
        playRetarget = Rand.double(0.25...0.5)

        guard let playmate = nearestCompanion() else { return }
        let centre = origin.x + size.width / 2
        let theirs = playmate.x + size.width / 2
        // Close enough to be playing *with* her rather than walking into her: the
        // separation below holds the distance, so the pair circles instead of
        // merging.
        guard abs(theirs - centre) > personalSpace else {
            wanderTargetX = nil
            return
        }
        wanderTargetX = playmate.x
    }

    private func nearestCompanion() -> CGPoint? {
        companions.min {
            hypot($0.x - origin.x, $0.y - origin.y) < hypot($1.x - origin.x, $1.y - origin.y)
        }
    }

    /// Step out of another pet's way. Positional rather than a force: the push
    /// decays to nothing at `personalSpace`, so two cats settle apart instead of
    /// springing at each other forever.
    private func separateFromCompanions(_ dt: Double, region: CGRect) {
        guard !companions.isEmpty, !isDragging else { return }
        let centre = origin.x + size.width / 2
        for companion in companions {
            // Only pets on the same footing get in each other's way: one on a
            // window ledge and one on the floor are not stacked.
            guard abs(origin.y - companion.y) < size.height * 0.6 else { continue }
            let gap = centre - (companion.x + size.width / 2)
            // Two animals in a brawl lean into each other, so the space they keep
            // is smaller — otherwise the rule that stops them stacking also stops
            // them ever touching.
            // Resting company piles up: two loafing pookies are allowed to lean
            // on each other, which is the whole charm of a pile of cats.
            let piling = isResting && abs(velocity.dx) < 4
            let space = isScuffling
                ? personalSpace * 0.5
                : (piling ? personalSpace * 0.72 : personalSpace)
            guard abs(gap) < space else { continue }
            let ease = (space - abs(gap)) * CGFloat(dt) * 1.6
            origin.x += (gap >= 0 ? 1 : -1) * min(ease, 0.75)
        }
        origin.x = min(max(origin.x, region.minX - 30), region.maxX - size.width + 30)
    }

    // MARK: - Teleporting between displays

    /// Which half of the blink is playing, if either.
    enum TeleportPhase: String {
        case none
        case leaving
        case arriving
    }

    /// How long each half of the blink takes. Short enough that a missing cat is
    /// never a mystery, long enough that the swivel and the poof are seen rather
    /// than inferred.
    static let teleportHalfSeconds: Double = 0.5

    private(set) var teleportPhase: TeleportPhase = .none
    private var teleportProgress: Double = 0
    /// True while she is mid-blink, so the frame pump treats it as an animation
    /// rather than as idle time and the rest ladder leaves her alone.
    var isTeleporting: Bool { teleportPhase != .none }

    /// A cat on a two-monitor desk that only ever lives on one of them is half a
    /// pet. This is the whole mechanic: wait a jittered minute, vanish in a twist
    /// of light and fur, and be somewhere else.
    private func updateTeleport(_ dt: Double) {
        if teleportPhase != .none {
            teleportProgress += dt / Self.teleportHalfSeconds
            guard teleportProgress >= 1 else { return }

            if teleportPhase == .leaving {
                // The move happens while she is not on screen to see it, which is
                // what makes it a blink rather than a slide.
                _ = teleportToRandomScreen()
                teleportPhase = .arriving
            } else {
                teleportPhase = .none
                // She lands on the way back in, so the squash is the arrival.
                squashKick = 0.55
            }
            teleportProgress = 0
            return
        }

        guard teleportEnabled, desktop.visibleFrames.count > 1 else { return }
        // She does not blink out of your hand, out of mid-air, out of a
        // sentence, out of a nap, or out of a game of chase.
        guard !isDragging, !isAirborne, !isCrouching, !isTalking, !isAsleep,
              !isPlaying, !isScuffling else { return }

        teleportInSeconds -= dt
        guard teleportInSeconds <= 0 else { return }
        rescheduleTeleport()
        beginTeleport()
    }

    /// Re-roll the blink timer: the next hop lands somewhere inside the cadence
    /// the settings asked for, not exactly on it.
    func rescheduleTeleport() {
        teleportInSeconds = teleportCadence.seconds * Rand.double(0.65...1.35)
    }

    /// Start a blink: out, move, in. Returns false when she is in no state to go.
    @discardableResult
    func beginTeleport() -> Bool {
        guard !isTeleporting, desktop.visibleFrames.count > 1 else { return false }
        guard !isDragging, !isAirborne, !isCrouching, !isTalking, !isAsleep,
              !isPlaying, !isScuffling else { return false }
        teleportPhase = .leaving
        teleportProgress = 0
        // She is not walking anywhere: the blink is the locomotion.
        wanderTargetX = nil
        return true
    }

    /// Move her to a random spot on another display. Instant and public on
    /// purpose: this is the primitive the blink wraps, and what the selftest can
    /// drive without waiting out an animation.
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
            && wanderTargetX == nil && !isPlaying && !isTeleporting && !isScuffling
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
        // A nap that ends in a bow usually ends in a stretch *up*, too.
        noteWaking()
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
        // A penguin does not trot: past a walk it goes down on its belly and
        // slides, which is the second gait the bird species asked for and costs
        // no new art — it is the lying shape, moving.
        if species.traits.slides, wanderTargetX != nil, abs(velocity.dx) > trotThreshold {
            return .lie
        }
        if wanderTargetX != nil || isPlaying || isTeleporting || isScuffling { return .stand }
        // The ladder ends curled: a donut is what a long nap looks like, and it
        // is the shape that reads as "gone" rather than "dozing".
        if isAsleep { return idleSeconds > sleepAfterSeconds + 20 ? .curl : .lie }
        if reachSeconds > 0 { return .reachUp }
        if peekSeconds > 0 { return .peek }
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
        // Remember where this jump is going. The plan is jittered — that is what
        // stops every jump from the same spot landing in the same place — so the
        // flight and the test that checks it have to agree on *this* plan rather
        // than on a second call to `planJump`.
        jumpTarget = plan.target
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

        var candidates: [(plan: JumpPlan, score: CGFloat, owner: String, top: CGFloat)] = []

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

            // Where she lands, not just where she stands: a jump that always
            // ends directly above the launch point is the "same spot every time"
            // the human noticed. Spread it along the ledge, biased to nearby.
            let spread = (maxX - minX) * jumpLandingSpread
            let targetX = min(max(origin.x + Rand.cg(-spread...spread), minX), maxX)
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
            // speed. And integrate it the way the physics *actually* does it —
            // `v *= drag^dt` once per frame, then `x += v * dt` — rather than as a
            // continuous curve: the two differ by a factor that grows with the
            // flight time, which is why long jumps used to land a fifth of the
            // way short while short ones looked fine.
            let perFrame = pow(airDrag, 1.0 / 60.0)
            let dragIntegral = (1.0 / 60.0) * perFrame * (1 - pow(airDrag, flight)) / (1 - perFrame)
            let vx = dx / CGFloat(dragIntegral)
            guard vy <= maxJumpSpeed, hypot(vx, vy) <= maxLaunchSpeed else { continue }

            // The arc has to fit under the ceiling, or the clamp cuts it short.
            let apex = origin.y + vy * vy / (2 * gravity)
            guard apex <= region.maxY - size.height + 2 else { continue }

            var score = abs(dx) + rise * 0.25
            // The frontmost app is a *preference*, not an obsession: at -260 she
            // spent her life on whichever window happened to be in front.
            if let preferred = preferredPlatformOwner, platform.ownerName == preferred {
                score -= 60
            }
            // Not the window she is already standing on, and not one she has just
            // jumped to: the same ledge every time reads as a bug, not as a pet.
            if let standing = supportPlatform(), standing.ownerName == platform.ownerName {
                score += 600
            }
            if recentJumpOwners.contains(platform.ownerName) {
                score += 180
            }
            // A little noise, so two equally good ledges are not always resolved
            // the same way.
            score += Rand.cg(-45...45)

            let heading: Double
            if dx > 2 { heading = 1 } else if dx < -2 { heading = -1 } else { heading = facing }
            candidates.append((
                plan: JumpPlan(
                    velocity: CGVector(dx: vx, dy: vy),
                    facing: heading,
                    target: CGPoint(x: targetX, y: platform.top)
                ),
                score: score,
                owner: platform.ownerName,
                top: platform.top
            ))
        }

        guard !candidates.isEmpty else { return nil }

        // Sometimes she goes for the highest thing she can reach rather than the
        // easiest one. That is what puts her on the tops of *other* windows
        // instead of on the same big one all day — sometimes, not always.
        let chosen: (plan: JumpPlan, score: CGFloat, owner: String, top: CGFloat)?
        if Rand.bool(0.32), let highest = candidates.max(by: { $0.top < $1.top }) {
            chosen = highest
        } else {
            chosen = candidates.min { $0.score < $1.score }
        }

        if let chosen {
            recentJumpOwners.append(chosen.owner)
            if recentJumpOwners.count > 3 { recentJumpOwners.removeFirst() }
        }
        return chosen?.plan
    }

    /// Keep her on a display, or let her cross onto the one next door.
    ///
    /// A wall is only a wall when there is nothing on the other side of it. With
    /// a monitor attached, the edge of a display is a *seam*: she walks across it
    /// rather than bouncing off an invisible wall, which is what she used to do
    /// on a two-monitor desk.
    ///
    /// Returns true when she was stopped, so a thrown pookie still bounces off a
    /// real wall.
    private func crossOrBounce(_ region: CGRect) -> Bool {
        let maxX = region.maxX - size.width
        guard origin.x < region.minX || origin.x > maxX else { return false }

        let direction: CGFloat = origin.x > maxX ? 1 : -1
        guard let neighbour = desktop.neighbour(of: region, direction: direction) else {
            origin.x = min(max(origin.x, region.minX), maxX)
            return true
        }

        // Crossing at floor level lands on the neighbour's floor; crossing higher
        // up keeps her altitude and lets gravity finish the job. Either way she
        // has to end up inside the new display, or the next frame's region lookup
        // would not find it.
        if abs(origin.y - region.minY) < 3 { origin.y = neighbour.minY }
        origin.y = min(max(origin.y, neighbour.minY), neighbour.maxY - size.height)
        return false
    }

    private func integrate(_ dt: Double) {
        // Prefer the region she was already in: a point in the seam gap between
        // two displays matches neither, and falling back to nearest-by-centre can
        // pick the one she just left, which reads as a bounce at the boundary.
        let region = desktop.region(containing: origin, preferring: lastRegion)
        var v = velocity
        let previousY = origin.y

        v.dy -= gravity * CGFloat(dt)
        // Air resistance. Without this, a flung cat keeps its release velocity
        // for the whole flight and ricochets across every display before it
        // stops. Halves over roughly two seconds.
        v.dx *= CGFloat(pow(airDrag, dt))
        origin.x += v.dx * CGFloat(dt)
        origin.y += v.dy * CGFloat(dt)

        lastRegion = region
        // Walls — but only where there is actually a wall.
        if crossOrBounce(region) {
            v.dx = (origin.x <= region.minX ? abs(v.dx) : -abs(v.dx)) * 0.5
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
        // Company before her own decisions: stepping out of another cat's way is
        // not a decision she made, and it must not be able to cancel a walk she
        // did choose.
        separateFromCompanions(dt, region: region)
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
        guard wanderEnabled, grounded, !isDragging, stateProfile?.wanders ?? true else {
            if !grounded { wanderTargetX = nil }
            return
        }

        if let target = wanderTargetX {
            let delta = target - origin.x
            if abs(delta) < 8 {
                wanderTargetX = nil
                wanderCountdown = Rand.double(7...18)
            } else {
                let speed = (abs(delta) > trotThreshold ? trotSpeed : walkSpeed) * CGFloat(speedBoost)
                velocity.dx = (delta > 0 ? 1 : -1) * min(speed, abs(delta) * 1.6)
                facing = delta > 0 ? 1 : -1
            }
            return
        }

        // Do not *start* anything while she is settled into a rest, or while she
        // is chasing a playmate: a cat that has lain down does not get up on a
        // timer. The loaf ends by its own clock (see `desiredRestingShape`), the
        // sit is the run-up to sleep, and a sleeping cat must not stand up and
        // wander off mid-nap.
        guard !isResting, !isPlaying, !isTeleporting, !isScuffling else { return }

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
        // Clear the transient channels before anything sets them. The pose is a
        // persistent property, and these five are only *written* while their
        // condition holds — so without this, a punch, a kick, a wash or a
        // tail-chase left at its last value sticks to her for the rest of the
        // session. That is what a pookie standing still with one leg out sideways
        // for no reason is: the last frame of a brawl she finished ten minutes ago.
        pose.punch = 0
        pose.kick = 0
        pose.groom = 0
        pose.spin = 0
        pose.impact = 0

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
        applyFaceOverrides()

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

        pose.species = species
        pose.pattern = pattern


        // The blink, as the one number the renderer needs: out is her going, in
        // is her arriving.
        switch teleportPhase {
        case .none: pose.vanish = 0
        case .leaving: pose.vanish = teleportProgress
        case .arriving: pose.vanish = max(0, 1 - teleportProgress)
        }

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

        // The scrap is applied last, on purpose: it is the one thing she does
        // that has to override the walk cycle and the mouth decay rather than be
        // composed with them.
        // Being hit: a squint, an open mouth, the head snapping away from the
        // blow, and a stagger. Without this a punch is a gesture at nobody.
        if hurtSeconds > 0 {
            let fade = CGFloat(max(0, min(1, hurtSeconds / 0.42)))
            // The squint is applied in `updateBlink`, which runs after this and
            // owns the channel: written here it was silently overwritten, which is
            // why being punched never actually squinted.
            pose.mouthOpen = max(pose.mouthOpen, 0.95 * fade)
            pose.tilt = pose.tilt + Double(hurtDirection) * 0.14 * Double(fade)
            pose.hopOffset = max(pose.hopOffset, 1.3 * fade)
        }

        // Grooming: a foreleg comes up to the muzzle and she washes behind it.
        if groomSeconds > 0 {
            let progress = 1 - groomSeconds / 2.0
            pose.groom = min(1, max(0, sin(progress * .pi) * 1.6))
        }

        // A tail-chase: the whole body turns on the spot, one way then back,
        // with the tail whipping after it.
        if spinSeconds > 0 {
            let progress = 1 - spinSeconds / 1.4
            pose.spin = sin(progress * 2 * .pi) * 0.55
        }

        // A sneeze is a hop, a shake and a squint, over in half a second.
        if sneezeSeconds > 0 {
            let peak = sin((1 - sneezeSeconds / 0.45) * .pi)
            pose.hopOffset = max(pose.hopOffset, peak * 2.2)
            pose.earTwitch = max(pose.earTwitch, peak * 0.5)
            // Squint in `updateBlink`, for the same reason as the flinch.
        }

        // Kneading: settled on something, happy, pressing her paws in a rhythm.
        // Drawn with the punch channel, because a knead *is* a small punch.
        if isResting, supportPlatform() != nil, !isAsleep, !isScuffling {
            let press = sin(time * 4.2)
            pose.punch = max(pose.punch, press * 0.28)
            pose.mouthOpen = max(pose.mouthOpen, 0.08)
        }

        // A head-bump: when the pointer is close, lean into it. Unprompted
        // affection is the thing a desktop pet is for.
        if let cursor, !isDragging, !isAirborne, sneezeSeconds <= 0 {
            let mine = screenPoint(designX: CatGeometry.design / 2, designY: pose.anatomy.headCenter.y)
            let gap = hypot(cursor.x - mine.x, cursor.y - mine.y)
            if gap < 90 {
                let lean = (1 - gap / 90) * 0.55
                pose.tilt = max(pose.tilt, lean * (cursor.x > mine.x ? 1 : -1) * 0.12)
                if gap < 46 { pose.hopOffset = max(pose.hopOffset, 0.8) }
            }
        }

        if isScuffling {
            // A one-two: the paws alternate about twice a second, with a hop
            // under each punch and the mouth open between them, so it reads as a
            // scrap rather than as a seizure.
            let beat = sin(scuffleSeconds * 13)
            let swing = sin(scuffleSeconds * 6.5)
            pose.hopOffset = max(pose.hopOffset, CGFloat(max(0, beat)) * 2.6)
            pose.mouthOpen = max(pose.mouthOpen, CGFloat(max(0, -beat)) * 0.85)
            // Every other swing is a kick rather than a punch, counted off the
            // bout's own clock so the two cannot drift apart: a scrap of nothing
            // but punches reads as shadow-boxing.
            let swingIndex = Int((scuffleLength - scuffleSeconds) / 0.48)
            if swingIndex % 2 == 0 {
                pose.punch = swing * 1.15
            } else {
                pose.kick = swing * 1.15
            }
            // The burst lands on the way through, not at the top of the swing.
            pose.impact = max(0, 1 - abs(swing) * 2.4)
        }

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

    /// Squints that ride *over* the blink timeline.
    ///
    /// This function owns `pose.blink`, so anything that wants to narrow her eyes
    /// has to say so here. The flinch and the sneeze both used to write the channel
    /// from `updatePose`, which runs first — so the timeline overwrote them every
    /// frame and neither ever showed.
    private func applyFaceOverrides() {
        if hurtSeconds > 0 {
            let fade = CGFloat(max(0, min(1, hurtSeconds / 0.42)))
            pose.blink = max(pose.blink, 0.8 * fade)
        }
        if sneezeSeconds > 0 {
            let peak = sin((1 - sneezeSeconds / 0.45) * .pi)
            pose.blink = max(pose.blink, peak * 0.8)
        }
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

    /// The gaze is smooth in *screen* space and stored in design space.
    ///
    /// That split is the whole fix for "her eyes look the wrong way": the
    /// renderer mirrors design space for a left-facing cat, so an offset aimed
    /// without the facing travels the wrong way along the screen — and it is
    /// wrong exactly while she is facing away (walking left, being carried, or
    /// with the cursor close enough that she has not turned). Smoothing in
    /// screen space also keeps the pupils on the cursor *through* a turn, since
    /// the flip is a mirror about her centre and the aim does not change with it.
    private var gazeScreenX: Double = 0
    private var gazeScreenY: Double = 0

    /// Where the pupils point on screen: `+1` right, `-1` left, whatever way she
    /// happens to be facing. The pose carries the design-space offset, which the
    /// facing flip mirrors; this is the honest answer to "is she looking at it?".
    var gazeDirectionOnScreen: Double { pose.gazeX * facingDirection }

    private func updateGaze(_ dt: Double) {
        guard followCursor, let cursor else {
            let relax = min(1, dt * 4)
            gazeScreenX += (0 - gazeScreenX) * relax
            gazeScreenY += (0 - gazeScreenY) * relax
            pose.gazeX = gazeScreenX * facing
            pose.gazeY = gazeScreenY
            return
        }

        if let last = lastCursor, hypot(cursor.x - last.x, cursor.y - last.y) > 1.5 {
            noteInteraction()
        }
        lastCursor = cursor

        let headScreen = screenPoint(designX: 50, designY: pose.anatomy.eyeY)
        let dx = cursor.x - headScreen.x
        let dy = cursor.y - headScreen.y
        let distance = max(1, hypot(dx, dy))
        let reach = min(1.0, Double(distance / 240))
        let targetX = Double(dx / distance) * reach
        let targetY = Double(dy / distance) * reach

        // Turn to face the cursor once it is clearly off to one side, before the
        // gaze is written, so the aim is taken through the facing she is about
        // to have rather than the one she is leaving.
        if !isDragging, wanderTargetX == nil, abs(dx) > 110 {
            facing = dx > 0 ? 1 : -1
        }

        let follow = min(1, dt * 9)
        gazeScreenX += (targetX - gazeScreenX) * follow
        gazeScreenY += (targetY - gazeScreenY) * follow
        pose.gazeX = gazeScreenX * facing
        pose.gazeY = gazeScreenY
    }

    private func resolveMood(sleepy: Bool, airborne: Bool, walking: Bool) -> CatMood {
        // An emote is imposed from outside and wins over what she is doing: a producer
        // asking for `love` means now, not when she next happens to be idle.
        if emoteSeconds > 0, let emoteMood { return emoteMood }
        if let forced = stateProfile?.mood { return forced }
        if isDragging { return .dragged }
        if airborne && abs(velocity.dy) > 700 { return .alarmed }
        // A cat in a chase is playing, and the happy face already has the ears
        // up, the tail faster and the blush — which is the whole expression.
        // A scrap is not a happy face: flattened ears, wide eyes and a hiss is
        // what a small fight looks like on this cat.
        if hurtSeconds > 0 { return .alarmed }
        if isScuffling { return .alarmed }
        if isPlaying { return .happy }
        if sleepy { return .sleepy }
        if let cursor, followCursor {
            let headScreen = screenPoint(designX: 50, designY: pose.anatomy.headCenter.y)
            if hypot(cursor.x - headScreen.x, cursor.y - headScreen.y) < 90 { return .curious }
        }
        if walking { return .walking }
        return .idle
    }

    var facingDirection: Double { facing }
}
