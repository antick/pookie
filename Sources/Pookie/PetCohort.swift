import AppKit

/// Owns the pets.
///
/// One Pookie is a pet; several are a colony, and everything that only makes
/// sense for a group lives here: how many there can be, who stands where, who
/// plays with whom, and the frame budget they share. A single pet is unaffected —
/// the cohort does nothing to her that the settings did not ask for.
final class PetCohort {
    /// The population the settings offer. Five is one of each species, which is
    /// the number that reads as a little gang rather than as a crowd — and five
    /// at the idle tier is a quarter of the cost of ten.
    static let maximumPets = 5
    /// Total drawn frames per second, shared evenly across the pets. One pet's
    /// own tiers sit below this, so the budget only starts to bite at three or
    /// four; five get 24 fps each, which is the tier a walking cat already uses.
    /// Five pets on this renderer are still five pets' worth of software
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
    /// Builds one pet's right-click menu. Set by the app shell: the menu items
    /// live with the app's other menus, and this type is not the menu.
    var contextMenuBuilder: ((PetWindowController) -> NSMenu?)?

    /// Everyone is off the desk. The colony-wide toggle uses this rather than
    /// asking the first pet, because pets are hidden one at a time now.
    var allHidden: Bool { !pets.isEmpty && pets.allSatisfy(\.isHiddenByUser) }
    /// At least one is off the desk, so the colony-wide item offers to bring them
    /// all back rather than hiding the rest.
    var someHidden: Bool { pets.contains { $0.isHiddenByUser } }
    /// How many are actually being drawn. A hidden pet costs nothing, so it should
    /// not be holding a share of the frame budget either.
    var visibleCount: Int { pets.filter { !$0.isHiddenByUser }.count }
    var isRaisedAboveEverything: Bool { pets.first?.isRaisedAboveEverything ?? false }
    /// The pet a producer talks through when it does not name one: the one the
    /// menu marks as the default.
    var spokespet: PetWindowController? {
        guard !pets.isEmpty else { return nil }
        let index = min(max(AppConfig.shared.defaultCritter, 0), pets.count - 1)
        return pets[index]
    }

    /// The shared colony clock, rate-limited here rather than given its own
    /// timer: a colony where every pet is occluded or hidden stops ticking, and
    /// costs nothing at all.
    private var lastSync: Double = 0
    private static let syncInterval: Double = 0.05
    private var playCountdown: Double = Rand.double(20...50)
    /// Scraps are more frequent than chases but still not a chained brawl.
    private var scuffleCooldown: Double = Rand.double(6...16)

    // MARK: - Population

    @discardableResult
    func spawn(species: PetSpecies? = nil, announce: Bool = true) -> PetWindowController? {
        guard Self.canAddPet(having: pets.count) else { return nil }

        let config = AppConfig.shared
        // The saved roster decides what is on the desk; anything past the end of
        // it is the next animal nobody has yet, which is what makes
        // `Pookie --pets 5` hand you one of each.
        let critter: CritterConfig
        if let species {
            critter = CritterConfig(species)
            config.roster.append(critter)
        } else if pets.count < config.roster.count {
            critter = config.roster[pets.count]
        } else {
            critter = nextCritter()
            config.roster.append(critter)
        }

        let pet = PetWindowController(
            critter: critter,
            personalScale: Rand.double(0.88...1.12),
            startOrigin: homeOrigin(slot: pets.count)
        )
        pet.cohort = self
        pets.append(pet)
        applyColonySettings()

        if announce, config.chatty {
            pet.say(PetChatter.arrived(), duration: 1.6)
        }
        Log.info("pet \(pets.count)/\(Self.maximumPets) up (\(critter.species.name), \(critter.coat.name))")
        return pet
    }

    /// Send the newest pet home.
    ///
    /// Kept as the M8 `despawn` verb, but it is no longer what the menu calls:
    /// the colony is addressed by position now, so you can take out the one you
    /// are pointing at rather than peeling them off the top. The last one stays
    /// either way — quitting is how you get rid of the pet you cannot quit.
    @discardableResult
    func despawn() -> Bool {
        removePet(at: pets.count - 1)
    }

    /// The first animal nobody is, in the coat that makes it look like itself —
    /// so adding a pet adds a *different* pet. Past the five species it falls
    /// back to the first coat nobody is wearing.
    private func nextCritter() -> CritterConfig {
        let speciesInUse = Set(pets.map(\.critter.species))
        if let species = PetSpecies.allCases.first(where: { !speciesInUse.contains($0) }) {
            return CritterConfig(species)
        }
        let coatsInUse = Set(pets.map(\.critter.coat))
        let coat = CatSkin.allCases.first { !coatsInUse.contains($0) }
            ?? CatSkin.allCases[pets.count % CatSkin.allCases.count]
        return CritterConfig(species: .cat, coat: coat)
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
        let fps = Self.perPetFPS(petCount: max(1, visibleCount))
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

        // Company close enough to touch is its own trigger: whether they arrived
        // by chasing each other or by sitting down side by side, two animals this
        // close will have a go at each other.
        scuffleCooldown -= elapsed
        if scuffleCooldown <= 0, startScuffleIfClose() { return }

        playCountdown -= elapsed
        guard playCountdown <= 0 else { return }
        playCountdown = Rand.double(20...50)
        startPlayBout()
    }

    /// Two pets within a paw's length of each other, on the same footing, will
    /// scrap. Returns true when a bout started, so the caller does not also
    /// start a chase in the same tick.
    @discardableResult
    private func startScuffleIfClose() -> Bool {
        let ready = pets.filter { $0.motion.canScuffle }
        guard ready.count >= 2 else { return false }

        for i in ready.indices {
            for j in ready.indices where j > i {
                let a = ready[i].motion
                let b = ready[j].motion
                guard abs(a.origin.y - b.origin.y) < a.size.height * 0.6 else { continue }
                guard abs(a.origin.x - b.origin.x) < a.personalSpace * 1.35 else { continue }

                let bout = Rand.double(1.4...2.6)
                guard a.startScuffle(bout) else { continue }
                b.startScuffle(bout * Rand.double(0.8...1.2))
                scuffleCooldown = Rand.double(8...20)
                // One of them says something, once.
                if AppConfig.shared.chatty, Rand.bool(0.7) {
                    ready[i].say(PetChatter.scuffling(), duration: 1.3)
                }
                Log.debug("scuffle between \(ready[i].critter.species.rawValue) and \(ready[j].critter.species.rawValue)")
                return true
            }
        }
        return false
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

    /// Re-roll every pet's blink timer after the cadence setting moved.
    func applyTeleportCadence() {
        for pet in pets {
            pet.motion.teleportCadence = AppConfig.shared.teleportCadence
            pet.motion.rescheduleTeleport()
        }
    }

    func setTeleporting(_ enabled: Bool) {
        for pet in pets { pet.motion.teleportEnabled = enabled }
    }

    /// Change what one pet is, and remember it.
    func setCritter(_ critter: CritterConfig, at index: Int) {
        guard pets.indices.contains(index) else { return }
        pets[index].apply(critter: critter)
        if AppConfig.shared.roster.indices.contains(index) {
            AppConfig.shared.roster[index] = critter
        }
    }

    /// Make one pet the one that answers producers.
    func makeDefault(index: Int) {
        guard pets.indices.contains(index) else { return }
        AppConfig.shared.defaultCritter = index
    }

    func setHidden(_ hidden: Bool) {
        for pet in pets { pet.setHidden(hidden) }
    }

    /// Hide or show one pet, by its place in the colony.
    func setHidden(_ hidden: Bool, at index: Int) {
        guard pets.indices.contains(index) else { return }
        pets[index].setHidden(hidden)
        applyColonySettings()
    }

    /// Take one pet off the desk, whichever one it is — not just the newest.
    @discardableResult
    func removePet(at index: Int) -> Bool {
        guard pets.count > 1, pets.indices.contains(index) else { return false }
        let pet = pets.remove(at: index)
        pet.close()
        if AppConfig.shared.roster.indices.contains(index) {
            AppConfig.shared.roster.remove(at: index)
        }
        AppConfig.shared.defaultCritter = min(
            AppConfig.shared.defaultCritter,
            max(0, AppConfig.shared.roster.count - 1)
        )
        applyColonySettings()
        Log.info("pet removed from the middle, \(pets.count)/\(Self.maximumPets) left")
        return true
    }

    /// The frame rate each pet gets, given how many are on screen. Pure, because
    /// "hiding two of five gives the rest the three-pet rate" is a claim worth
    /// checking without a window server.
    static func frameShare(total: Int, hidden: Int) -> Double {
        perPetFPS(petCount: max(1, total - hidden))
    }

    /// True when the whole colony is off the desk.
    var isHiddenByUser: Bool { allHidden }

    func toggleHidden() {
        setHidden(!allHidden)
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
