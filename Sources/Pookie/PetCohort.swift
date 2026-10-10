import AppKit

/// Owns the pets.
///
/// One Pookie is a pet; several are a colony, and everything that only makes
/// sense for a group lives here: how many there can be, who stands where, who
/// plays with whom, and the frame budget they share. A single pet is unaffected —
/// the cohort does nothing to her that the settings did not ask for.
final class PetCohort {
    /// The population the settings offer. Ten, because the roster can hold every
    /// animal and the desk is the thing that has a limit; the frame budget below
    /// is what keeps it honest.
    static let maximumPets = 10
    /// The colony's frame budget, in **milliseconds of drawing per second**.
    ///
    /// A time budget rather than a frame count, because that is what "an
    /// accounting of who spent what" means: a pookie whose frame costs 1 ms can
    /// run twice as often as one that costs 2 ms inside the same budget, where a
    /// flat frame count gave them both the same and let the expensive one spend
    /// twice as much CPU. 200 ms/s is a little over the old flat 120 frames at the
    /// measured cost, so nothing got slower.
    static let drawBudgetMillisecondsPerSecond: Double = 200

    /// The frame count the budget works out to when every pet costs the nominal
    /// figure. No longer what the colony uses — `frameRates` is — but it is the
    /// number the tests state the floor and ceiling against.
    static let totalFrameBudget: Double = 120

    /// Pure, so the cap is checkable without a window server.
    static func canAddPet(having count: Int) -> Bool { count < maximumPets }

    /// The share of the budget one pet gets, when every pet costs the same.
    /// Never below the sleep tier: a cat that cannot be seen to breathe is not a
    /// pet.
    static func perPetFPS(petCount: Int) -> Double {
        guard petCount > 0 else { return 0 }
        return max(8, min(60, totalFrameBudget / Double(petCount)))
    }

    /// Frame rates for a set of pets, given what each one costs to draw.
    ///
    /// Pure and total: the cheapest pet is served first (it can be drawn most
    /// often for the same milliseconds), every pet keeps at least the sleep tier,
    /// and nothing exceeds the ceiling. Water-filling rather than proportional
    /// shares, because a pet that costs nothing should not be handed a share it
    /// cannot use while a costly one starves.
    static func frameRates(
        costs: [Double],
        budget: Double = drawBudgetMillisecondsPerSecond,
        floor: Double = 8,
        ceiling: Double = 60
    ) -> [Double] {
        guard !costs.isEmpty else { return [] }
        let safe = costs.map { $0 > 0.05 ? $0 : 1.5 }

        // Every pet's floor is guaranteed first, then the rest of the budget is
        // handed out a millisecond at a time to whoever can buy the most frames.
        var rates = safe.map { _ in floor }
        var remaining = budget - safe.reduce(0) { $0 + floor * $1 }
        guard remaining > 0 else { return rates }

        // Cheapest first: one extra frame costs this pet's cost in milliseconds.
        let order = safe.indices.sorted { safe[$0] < safe[$1] }
        for index in order {
            guard rates[index] < ceiling else { continue }
            let affordable = remaining / safe[index]
            let room = ceiling - rates[index]
            let added = min(affordable, room)
            rates[index] += added
            remaining -= added * safe[index]
            if remaining <= 0 { break }
        }
        return rates.map { min(ceiling, max(floor, $0)) }
    }

    private(set) var pets: [PetWindowController] = []
    var count: Int { pets.count }
    /// Where the pet's own events go: `PROTOCOL.md` §6's `clicked`, `dragged`,
    /// `dropped` and `petted`. Set by the app shell, which owns the socket.
    var onEvent: ((String, [String: Any]) -> Void)?

    /// Emit one event, with the pet it happened to.
    func emit(_ event: String, pet: PetWindowController? = nil, data: [String: Any] = [:]) {
        var payload = data
        payload["pet"] = pet?.pookie.name ?? spokespet?.pookie.name ?? "pookie"
        onEvent?(event, payload)
    }

    /// Builds one pet's right-click menu. Set by the app shell: the menu items
    /// live with the app's other menus, and this type is not the menu.
    var contextMenuBuilder: ((PetWindowController) -> NSMenu?)?

    /// Everyone is off the desk. The colony-wide toggle uses this rather than
    /// asking the first pet, because pets are hidden one at a time now.
    var allHidden: Bool { !pets.isEmpty && pets.allSatisfy(\.isHiddenByUser) }
    /// At least one is off the desk, so the colony-wide item offers to bring them
    /// all back rather than hiding the rest.
    var someHidden: Bool { pets.contains { $0.isHiddenByUser } }

    /// The pet a producer talks through when it does not name one: the one the
    /// menu marks as the default.
    var spokespet: PetWindowController? {
        guard !pets.isEmpty else { return nil }
        let index = min(max(AppConfig.shared.boss, 0), pets.count - 1)
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

    /// Put one roster entry on the desk.
    @discardableResult
    private func spawn(entry: PookieConfig, announce: Bool = true) -> PetWindowController? {
        guard Self.canAddPet(having: pets.count) else { return nil }
        guard !pets.contains(where: { $0.pookie.species == entry.species }) else { return nil }

        let pet = PetWindowController(
            pookie: entry,
            personalScale: Rand.double(0.88...1.12),
            startOrigin: homeOrigin(slot: pets.count)
        )
        pet.cohort = self
        pets.append(pet)
        applyColonySettings()

        if announce, AppConfig.shared.chatty, !AppConfig.shared.quietMode {
            pet.say(PetChatter.arrived(), duration: 1.6)
        }
        Log.info("desk \(pets.count)/\(Self.maximumPets): \(entry.name) the \(entry.species.name) in \(entry.coat.name)")
        return pet
    }

    /// Put the collection on the desk: everything the roster says belongs there,
    /// in order, up to the cap.
    ///
    /// `--pets N` overrides how many come out for one run without touching the
    /// roster — which is what makes a headless run predictable.
    func spawnFromRoster() {
        let wanted = AppConfig.shared.startPets
        for (index, entry) in AppConfig.shared.roster.enumerated() {
            guard Self.canAddPet(having: pets.count) else { break }
            guard entry.onDesk else { continue }
            if let wanted, pets.count >= wanted { break }
            _ = index
            spawn(entry: entry, announce: false)
        }
        // `--pets N` may ask for more than the roster has on the desk: fill from
        // the collection, in order.
        if let wanted {
            for entry in AppConfig.shared.roster where pets.count < wanted {
                guard Self.canAddPet(having: pets.count) else { break }
                guard !pets.contains(where: { $0.pookie.species == entry.species }) else { continue }
                spawn(entry: entry, announce: false)
            }
        }
    }

    /// The whole collection: every animal configured, on the desk or not.
    var collection: [PookieConfig] { AppConfig.shared.roster }

    /// Add an animal to the collection. On the desk if there is room, otherwise
    /// kept and switched off — which is the point of a collection.
    @discardableResult
    func addToCollection(species: PetSpecies) -> Bool {
        guard !AppConfig.shared.roster.contains(where: { $0.species == species }) else { return false }
        let room = Self.canAddPet(having: pets.count)
        let entry = PookieConfig(species, onDesk: room)
        AppConfig.shared.roster.append(entry)
        if room { spawn(entry: entry) }
        applyColonySettings()
        return true
    }

    /// Take an animal out of the collection entirely.
    @discardableResult
    func removeFromCollection(species: PetSpecies) -> Bool {
        if let index = pets.firstIndex(where: { $0.pookie.species == species }) {
            guard pets.count > 1 else { return false }
            let pet = pets.remove(at: index)
            pet.close()
        }
        AppConfig.shared.roster.removeAll { $0.species == species }
        AppConfig.shared.boss = min(AppConfig.shared.boss, max(0, pets.count - 1))
        applyColonySettings()
        return true
    }

    /// Show one animal on the desk, or take it off without forgetting it.
    @discardableResult
    func setOnDesk(_ on: Bool, species: PetSpecies) -> Bool {
        guard let index = AppConfig.shared.roster.firstIndex(where: { $0.species == species }) else {
            return false
        }
        if on {
            guard Self.canAddPet(having: pets.count) else { return false }
            guard !pets.contains(where: { $0.pookie.species == species }) else { return true }
            AppConfig.shared.roster[index].onDesk = true
            return spawn(entry: AppConfig.shared.roster[index]) != nil
        }
        AppConfig.shared.roster[index].onDesk = false
        guard let petIndex = pets.firstIndex(where: { $0.pookie.species == species }) else { return true }
        guard pets.count > 1 else { return false }
        let pet = pets.remove(at: petIndex)
        pet.close()
        AppConfig.shared.boss = min(AppConfig.shared.boss, max(0, pets.count - 1))
        applyColonySettings()
        return true
    }

    /// Add an animal straight to the desk, which is what the menu's Add does.
    @discardableResult
    func spawn(species: PetSpecies? = nil, announce: Bool = true) -> PetWindowController? {
        let wanted = species ?? PetSpecies.allCases.first { candidate in
            !AppConfig.shared.roster.contains { $0.species == candidate }
        } ?? .cat
        guard addToCollection(species: wanted) else { return nil }
        guard let pet = pets.first(where: { $0.pookie.species == wanted }) else { return nil }
        if announce, AppConfig.shared.chatty, !AppConfig.shared.quietMode {
            pet.say(PetChatter.arrived(), duration: 1.6)
        }
        return pet
    }

    /// so adding a pet adds a *different* pet. Past the five species it falls
    /// back to the first coat nobody is wearing.
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
        // The budget is divided by what each pet actually costs to draw, so a
        // sleeping pookie frees frames for a running one instead of both getting
        // the same flat share. Hidden pets are not in the list at all: they are not
        // drawn, so they should not hold a share.
        let visible = pets.filter { !$0.isHiddenByUser }
        let rates = Self.frameRates(costs: visible.map(\.drawCostMilliseconds))
        var next = 0
        for pet in pets {
            pet.setExcludedPerchWindows(excluded)
            if pet.isHiddenByUser {
                pet.frameRateCap = 8
            } else {
                pet.frameRateCap = rates.indices.contains(next) ? rates[next] : 8
                next += 1
            }
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

        // Blows land. Whoever threw one, the one nearest them feels it — which is
        // the difference between a fight and two animals waving at each other.
        for attacker in pets where attacker.motion.isScuffling {
            guard attacker.motion.takePendingHit() else { continue }
            let victim = pets
                .filter { $0 !== attacker }
                .min { abs($0.motion.origin.x - attacker.motion.origin.x)
                    < abs($1.motion.origin.x - attacker.motion.origin.x) }
            victim?.motion.reactToHit(fromX: attacker.motion.origin.x)
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
                guard abs(a.origin.x - b.origin.x) < a.brawlRange else { continue }
                // Contact starts one on the spot. Three seconds of *nearness* is
                // for pookies who sit down near each other; two who walk into
                // each other do not wait.
                guard (a.isBrawlReady && b.isBrawlReady) || a.isInContact || b.isInContact else { continue }

                let bout = Rand.double(1.6...3.0)
                guard a.startScuffle(bout) else { continue }
                b.startScuffle(bout * Rand.double(0.8...1.2))
                // Long enough that a brawl is an event, short enough that two
                // neighbours who stay put will have another one.
                scuffleCooldown = Rand.double(6...16)
                // One of them says something, once.
                if AppConfig.shared.chatty, !AppConfig.shared.quietMode, Rand.bool(0.7) {
                    ready[i].say(PetChatter.scuffling(), duration: 1.3)
                }
                Log.debug("scuffle between \(ready[i].pookie.species.rawValue) and \(ready[j].pookie.species.rawValue)")
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
            if !AppConfig.shared.quietMode {
                pair.0.say(PetChatter.playing(), duration: 1.4)
            }
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
    func setPookie(_ pookie: PookieConfig, at index: Int) {
        guard pets.indices.contains(index) else { return }
        // Changing an animal's kind obeys the same rule as adding one: if
        // somebody else is already that animal, this is not allowed.
        if pookie.species != pets[index].pookie.species,
           pets.contains(where: { $0 !== pets[index] && $0.pookie.species == pookie.species }) {
            return
        }
        pets[index].apply(pookie: pookie)
        if AppConfig.shared.roster.indices.contains(index) {
            AppConfig.shared.roster[index] = pookie
        }
    }

    /// Make one pet the one that answers producers.
    func makeDefault(index: Int) {
        guard pets.indices.contains(index) else { return }
        AppConfig.shared.boss = index
    }

    func setHidden(_ hidden: Bool) {
        // Logged, because a hidden pet stops drawing and therefore stops reporting:
        // without this line, "did the hide work?" has no answer in the log.
        Log.info("pets \(hidden ? "hidden" : "shown")")
        for pet in pets { pet.setHidden(hidden) }
    }

    /// Every pet, for a system reason rather than a human one: the screen locked or
    /// the machine went to sleep.
    func setSystemPaused(_ paused: Bool) {
        Log.info("system pause \(paused ? "on" : "off") — \(paused ? "screen locked or asleep" : "back")")
        for pet in pets { pet.setSystemPaused(paused) }
    }

    /// Hide or show one pet, by its place in the colony.
    func setHidden(_ hidden: Bool, at index: Int) {
        guard pets.indices.contains(index) else { return }
        pets[index].setHidden(hidden)
        applyColonySettings()
    }

    /// Whether this animal can join: one of each, so a second bunny is not an
    /// option — a different *coat* on the bunny who is already here is, and that
    /// is what the coat menu is for.
    func canAdd(species: PetSpecies) -> Bool {
        Self.canAddPet(having: pets.count) && !pets.contains { $0.pookie.species == species }
    }

    /// Chattiness is a colony-wide setting, so it fans out.
    func applyChattiness() {
        for pet in pets { pet.setChatty(AppConfig.shared.chatty) }
    }

    /// Opacity and quiet mode are colony-wide, like everything else.
    func applyOpacity() {
        for pet in pets { pet.applyOpacity() }
    }

    func applyPrivacy() {
        for pet in pets { pet.applySharingPrivacy() }
    }

    /// Raise every pet over full-screen apps, and remember it for the ones that
    /// come later.
    var isRaisedAboveEverything = false

    func applyRaisedAboveEverything() {
        for pet in pets { pet.setRaisedAboveEverything(isRaisedAboveEverything) }
    }

    /// Change one pookie's markings. Free of everything else: any pattern on any
    /// animal in any coat.
    func setPattern(_ pattern: PookiePattern, at index: Int) {
        guard pets.indices.contains(index) else { return }
        var config = pets[index].pookie
        config.pattern = pattern
        pets[index].apply(pookie: config)
        if AppConfig.shared.roster.indices.contains(index) {
            AppConfig.shared.roster[index] = config
        }
    }

    /// Change one pookie, addressed by the animal it is. Species are unique in a
    /// collection, so the species *is* the key — which is what lets the settings
    /// window and the menu talk about the same pookie without sharing indices.
    private func update(species: PetSpecies, _ edit: (inout PookieConfig) -> Void) {
        guard let index = AppConfig.shared.roster.firstIndex(where: { $0.species == species }) else { return }
        var entry = AppConfig.shared.roster[index]
        edit(&entry)
        AppConfig.shared.roster[index] = entry
        if let pet = pets.first(where: { $0.pookie.species == species }) {
            pet.apply(pookie: entry)
        }
    }

    func rename(species: PetSpecies, to name: String) {
        update(species: species) { $0.name = PookieConfig.clean(name) }
    }

    /// Change what an animal *is*. Refused when somebody else is already that
    /// animal, because the collection keeps one of each.
    @discardableResult
    func changeSpecies(of species: PetSpecies, to newSpecies: PetSpecies) -> Bool {
        guard newSpecies != species else { return true }
        guard !AppConfig.shared.roster.contains(where: { $0.species == newSpecies }) else { return false }
        guard let index = AppConfig.shared.roster.firstIndex(where: { $0.species == species }) else {
            return false
        }
        AppConfig.shared.roster[index].species = newSpecies
        // The name and coat come with it: it is still the same pookie.
        if let pet = pets.first(where: { $0.pookie.species == species }) {
            pet.apply(pookie: AppConfig.shared.roster[index])
        }
        return true
    }

    func setCoat(_ coat: CatSkin, species: PetSpecies) {
        update(species: species) { $0.coat = coat }
    }

    func setPattern(_ pattern: PookiePattern, species: PetSpecies) {
        update(species: species) { $0.pattern = pattern }
    }

    /// Rename one pookie. The name is the human's, so nothing else keys off it.
    func renamePookie(at index: Int, to name: String) {
        guard pets.indices.contains(index) else { return }
        var config = pets[index].pookie
        config.name = PookieConfig.clean(name)
        pets[index].apply(pookie: config)
        if AppConfig.shared.roster.indices.contains(index) {
            AppConfig.shared.roster[index] = config
        }
    }

    /// Take one pet off the desk, whichever one it is — not just the newest.
    @discardableResult
    func removePet(at index: Int) -> Bool {
        guard pets.indices.contains(index) else { return false }
        return removeFromCollection(species: pets[index].pookie.species)
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
    func say(
        _ text: String,
        style: BubbleStyle = .plain,
        from producer: String = SpeechEngine.ownProducer
    ) -> SpeechOutcome {
        guard let pet = spokespet else { return .rejected("no_pet") }
        return pet.say(text, style: style, from: producer)
    }

    func hideBubble() {
        for pet in pets { pet.hideBubble() }
    }
}
