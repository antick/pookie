import AppKit

/// Owns the pets.
///
/// One Pookie is a pet; several are a colony, and everything that only makes
/// sense for a group lives here: how many there can be, who stands where, who
/// plays with whom, and the frame budget they share. A single pet is unaffected —
/// the cohort does nothing to her that the settings did not ask for.
final class PetCohort {
    /// The population the settings offer.
    static let maximumPets = 10
    /// Total drawn frames per second, shared evenly across the pets. One cat's
    /// own tiers sit below this, so the budget only starts to bite at three or
    /// four; ten cats get 12 fps each, which is the tier a sleeping cat already
    /// used. Ten cats on this renderer are still ten cats' worth of software
    /// rasterisation — that is the M1 SpriteKit work, not a tuning problem.
    static let totalFrameBudget: Double = 120

    /// Pure, so the cap is checkable without a window server.
    static func canAddPet(having count: Int) -> Bool { count < maximumPets }

    /// The share of the budget one pet gets. Never below the sleep tier: a cat
    /// that cannot be seen to breathe is not a pet.
    static func perPetFPS(petCount: Int) -> Double {
        guard petCount > 0 else { return 0 }
        return max(8, min(60, totalFrameBudget / Double(petCount)))
    }

    private(set) var pets: [PetWindowController] = []
    var count: Int { pets.count }
    var isHiddenByUser: Bool { pets.first?.isHiddenByUser ?? false }
    var isRaisedAboveEverything: Bool { pets.first?.isRaisedAboveEverything ?? false }
    /// The pet a producer talks through when it does not name one.
    var spokespet: PetWindowController? { pets.first }

    /// The shared colony clock, rate-limited here rather than given its own
    /// timer: a colony where every pet is occluded or hidden stops ticking, and
    /// costs nothing at all.
    private var lastSync: Double = 0
    private static let syncInterval: Double = 0.05
    private var playCountdown: Double = Rand.double(20...50)

    // MARK: - Population

    @discardableResult
    func spawn(announce: Bool = true) -> PetWindowController? {
        guard Self.canAddPet(having: pets.count) else { return nil }

        let pet = PetWindowController(
            skin: nextSkin(),
            personalScale: Rand.double(0.88...1.12),
            startOrigin: homeOrigin(slot: pets.count)
        )
        pet.cohort = self
        pets.append(pet)
        applyColonySettings()

        if announce, AppConfig.shared.chatty {
            pet.say(PetChatter.arrived(), duration: 1.6)
        }
        Log.info("pet \(pets.count)/\(Self.maximumPets) up (\(pet.skin.rawValue))")
        return pet
    }

    /// Send the newest pet home. The last one stays: quitting is how you get rid
    /// of the cat you cannot quit.
    @discardableResult
    func despawn() -> Bool {
        guard pets.count > 1 else { return false }
        let pet = pets.removeLast()
        pet.close()
        applyColonySettings()
        Log.info("pet removed, \(pets.count)/\(Self.maximumPets) left")
        return true
    }

    /// The first coat nobody is wearing, so a new pet is always a new cat.
    private func nextSkin() -> CatSkin {
        let taken = Set(pets.map(\.skin))
        return CatSkin.allCases.first { !taken.contains($0) }
            ?? CatSkin.allCases[pets.count % CatSkin.allCases.count]
    }

    /// Where a new pet appears, given the desk and the user's chosen start point.
    ///
    /// Pure, so the rule can be checked without a window server — and it is worth
    /// checking, because the first version of it silently overrode `--at x,y`.
    ///
    /// With a start point, the first pet goes exactly there and the rest line up
    /// to her right. Without one, they arrive in a row along the bottom of the
    /// display, spaced out rather than stacked.
    static func homeOrigin(
        slot: Int,
        region: CGRect,
        size: CGSize,
        start: CGPoint?,
        jitter: CGFloat = 0
    ) -> CGPoint {
        if let start {
            return CGPoint(x: start.x + CGFloat(slot) * (size.width + 24), y: start.y)
        }
        let width = max(1, region.width - size.width - 80)
        let step = width / CGFloat(maximumPets)
        let x = region.minX + 40 + CGFloat(min(slot, maximumPets - 1)) * step
        return CGPoint(x: x + jitter, y: region.minY)
    }

    /// The user naming a spot wins; otherwise the row along the bottom.
    private func homeOrigin(slot: Int) -> CGPoint {
        let region = NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return Self.homeOrigin(
            slot: slot,
            region: region,
            size: AppConfig.shared.petSize,
            start: AppConfig.shared.startOrigin,
            jitter: Rand.cg(-24...24)
        )
    }

    /// Everything a population change implies: who may stand on whom, and how
    /// the frame budget is divided.
    private func applyColonySettings() {
        var excluded: Set<Int> = []
        for pet in pets { excluded.formUnion(pet.ownWindowNumbers) }
        let fps = Self.perPetFPS(petCount: pets.count)
        for pet in pets {
            pet.setExcludedPerchWindows(excluded)
            pet.frameRateCap = fps
        }
    }

    // MARK: - The colony clock

    /// Push every pet's position to every other pet, and occasionally start a
    /// game. Called by each pet's frame pump; the rate limit is what keeps that
    /// from being ten times the work.
    func sync() {
        let now = CACurrentMediaTime()
        guard now - lastSync >= Self.syncInterval else { return }
        let elapsed = now - lastSync
        lastSync = now
        guard !pets.isEmpty else { return }

        let positions = pets.map(\.motion.origin)
        for (index, pet) in pets.enumerated() {
            var others = positions
            others.remove(at: index)
            pet.motion.companions = others
        }

        playCountdown -= elapsed
        guard playCountdown <= 0 else { return }
        playCountdown = Rand.double(20...50)
        startPlayBout()
    }

    /// Pick two pets who could plausibly notice each other, and let them chase.
    ///
    /// Same display, awake, not being held, not already playing, and within
    /// shouting distance: a cat on a monitor the other one cannot see cannot
    /// start a game with her.
    private func startPlayBout() {
        let ready = pets.filter { $0.motion.canPlay }
        guard ready.count >= 2 else { return }

        var pairs: [(PetWindowController, PetWindowController)] = []
        for i in ready.indices {
            for j in ready.indices where j > i {
                let a = ready[i].motion
                let b = ready[j].motion
                guard a.desktop.region(containing: a.origin) == b.desktop.region(containing: b.origin) else { continue }
                guard hypot(a.origin.x - b.origin.x, a.origin.y - b.origin.y) < 1600 else { continue }
                pairs.append((ready[i], ready[j]))
            }
        }
        guard let pair = pairs.randomElement() else { return }

        let bout = Rand.double(2.5...5)
        guard pair.0.motion.startPlay(bout) else { return }
        pair.1.motion.startPlay(bout * Rand.double(0.7...1.1))

        // One of them says something, if she is allowed to talk at all: two
        // bubbles at once is exactly the noise the speech rules exist to stop.
        if AppConfig.shared.chatty, Rand.bool(0.5) {
            pair.0.say(PetChatter.playing(), duration: 1.4)
        }
    }

    // MARK: - Shared settings
    //
    // Settings are colony-wide on purpose: "small" and "chatty" are properties of
    // the pet on your desk, not of one cat out of five.

    func applyPetScale() {
        for pet in pets { pet.applyPetScale() }
    }

    func setHidden(_ hidden: Bool) {
        for pet in pets { pet.setHidden(hidden) }
    }

    func toggleHidden() {
        setHidden(!isHiddenByUser)
    }

    func applyClickThroughMode() {
        for pet in pets { pet.applyClickThroughMode() }
    }

    /// Advance the shared mouse mode once, then hand it to every pet. Cycling it
    /// per pet would walk through the modes by however many pets there are.
    func cycleClickThrough() {
        let modes = ClickThroughMode.allCases
        let index = modes.firstIndex(of: AppConfig.shared.clickThroughMode) ?? 0
        AppConfig.shared.clickThroughMode = modes[(index + 1) % modes.count]
        applyClickThroughMode()
        Log.info("click-through mode -> \(AppConfig.shared.clickThroughMode.rawValue)")
    }

    func setPerching(_ enabled: Bool) {
        for pet in pets { pet.setPerching(enabled) }
    }

    func setJumping(_ enabled: Bool) {
        for pet in pets { pet.setJumping(enabled) }
    }

    func setChatty(_ enabled: Bool) {
        for pet in pets { pet.setChatty(enabled) }
    }

    func applyScreenSharePrivacy() {
        for pet in pets { pet.applyScreenSharePrivacy() }
    }

    func setRaisedAboveEverything(_ raised: Bool) {
        for pet in pets { pet.setRaisedAboveEverything(raised) }
    }

    func refreshScreens() {
        for pet in pets { pet.refreshScreens() }
    }

    /// "Bring Pookie home", for all of them: the row they arrived in.
    func bringAllHome() {
        for (index, pet) in pets.enumerated() {
            pet.motion.move(to: homeOrigin(slot: index), animated: false)
            pet.syncWindowFrame()
        }
    }

    /// Talk through the spokespet. Naming a pet is M4's problem; today a producer
    /// talks to the colony and the first cat answers.
    @discardableResult
    func say(_ text: String, style: BubbleStyle = .plain) -> SpeechOutcome {
        guard let pet = spokespet else { return .rejected("no_pet") }
        return pet.say(text, style: style)
    }

    func hideBubble() {
        for pet in pets { pet.hideBubble() }
    }
}
