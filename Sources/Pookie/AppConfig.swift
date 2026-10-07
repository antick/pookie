import AppKit

/// Which mouse events the pet's window consumes.
enum ClickThroughMode: String, CaseIterable {
    /// Only pixels the cat actually covers capture the mouse.
    ///
    /// Implemented by polling the cursor and toggling `ignoresMouseEvents`,
    /// NOT by `NSView.hitTest` alone: by the time `hitTest` runs the window
    /// server has already delivered the event to our window, so a nil result
    /// swallows the click rather than forwarding it. See
    /// `docs/MACOS-CONSTRAINTS.md` section 3.
    case silhouette
    /// The whole window rectangle captures the mouse. Always predictable.
    case solid
    /// The window ignores the mouse entirely; the pet becomes a pure observer.
    case passthrough

    var label: String {
        switch self {
        case .silhouette: return "Click through gaps"
        case .solid: return "Capture whole box"
        case .passthrough: return "Ignore mouse"
        }
    }
}

/// How big Pookie is drawn.
///
/// The window, the drawing and the behaviour geometry all scale together, so
/// this is a real size change rather than a zoom: her feet stay on the same spot
/// and the whole cat stays inside the window, which is why every size is
/// re-checked against the art envelope in `--selftest`.
enum CatScale: String, CaseIterable {
    case small
    case medium
    case large
    case huge

    var factor: CGFloat {
        switch self {
        case .small: return 0.7
        case .medium: return 1
        case .large: return 1.4
        case .huge: return 1.9
        }
    }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .huge: return "Extra large"
        }
    }
}

/// How often a pet blinks to another display, before the jitter.
///
/// A cadence rather than a number of seconds: what people actually want to say is
/// "every couple of minutes", and the motion layer jitters around whatever this
/// names so that a colony of five never blinks in unison.
enum TeleportCadence: String, CaseIterable {
    case brisk
    case normal
    case relaxed
    case rare
    case seldom

    var minutes: Double {
        switch self {
        case .brisk: return 1
        case .normal: return 2
        case .relaxed: return 5
        case .rare: return 10
        case .seldom: return 30
        }
    }

    var seconds: Double { minutes * 60 }

    var label: String {
        switch self {
        case .brisk: return "Every minute"
        case .normal: return "Every 2 minutes"
        case .relaxed: return "Every 5 minutes"
        case .rare: return "Every 10 minutes"
        case .seldom: return "Every 30 minutes"
        }
    }
}

/// One pet in the roster: what animal, and in what coat.
///
/// The roster is what "which pookie do I want loaded" means — the settings store
/// it, and the colony spawns exactly it.
struct CritterConfig: Equatable {
    var species: PetSpecies
    var coat: CatSkin

    init(species: PetSpecies, coat: CatSkin) {
        self.species = species
        self.coat = coat
    }

    /// A new animal wearing the coat that makes it look like itself.
    init(_ species: PetSpecies) {
        self.init(species: species, coat: species.defaultCoat)
    }

    static let tabbyCat = CritterConfig(species: .cat, coat: .tabby)

    /// The compact form the settings store keeps, e.g. `bunny:snow`.
    var encoded: String { "\(species.rawValue):\(coat.rawValue)" }

    init?(encoded: String) {
        let parts = encoded.split(separator: ":")
        guard parts.count == 2,
              let species = PetSpecies(rawValue: String(parts[0])),
              let coat = CatSkin(rawValue: String(parts[1]))
        else { return nil }
        self.init(species: species, coat: coat)
    }
}

/// A single mutable settings object.
///
/// The things a person would be annoyed to set twice persist: the roster, the
/// size, the cadences, the switches. Transient state — where a pet is, what she
/// is doing — deliberately does not; M8 owns the full preferences store, and
/// `docs/ROADMAP.md` says so.
final class AppConfig {
    static let shared = AppConfig()

    private let defaults: UserDefaults

    /// Whether changes are written to the settings store. `main.swift` turns this
    /// off when the command line overrides something: `--no-wander` is a flag for
    /// one run, and a flag that silently rewrites the saved settings is a bug the
    /// user cannot see coming.
    var persistsChanges = true

    private func store(_ value: Any, _ key: Key) {
        guard persistsChanges else { return }
        defaults.set(value, forKey: key.rawValue)
    }

    var clickThroughMode: ClickThroughMode = .silhouette {
        didSet { store(clickThroughMode.rawValue, .clickThrough) }
    }
    var wanderEnabled = true {
        didSet { store(wanderEnabled, .wander) }
    }
    var followCursor = true {
        didSet { store(followCursor, .followCursor) }
    }
    /// Land on the top edges of other apps' windows instead of falling past
    /// them. Permission-free (`CGWindowList` geometry only) and switchable,
    /// because "the cat sits on my window" is charming and "the cat sits on my
    /// window during a demo" is not.
    var perchEnabled = true {
        didSet { store(perchEnabled, .perch) }
    }
    /// Jump up onto a reachable window top by herself, rather than only perching
    /// when you drop her there. Separate from `perchEnabled` because a pet that
    /// leaps around unprompted is charming right up until it is not.
    var jumpEnabled = true {
        didSet { store(jumpEnabled, .jump) }
    }
    /// React to being petted, thrown, and perched on. Off means she only speaks
    /// when a producer tells her to.
    var chatty = true {
        didSet { store(chatty, .chatty) }
    }
    /// `NSWindow.sharingType = .none` hides the pet from screen sharing and
    /// captures. Deliberately off by default so screenshots still show Pookie.
    var hideFromScreenShare = false {
        didSet { store(hideFromScreenShare, .privacy) }
    }
    /// How big she is drawn. See `CatScale`.
    var petScale: CatScale = .medium {
        didSet { store(petScale.rawValue, .scale) }
    }
    /// Blink to another display every so often. Only does anything with more than
    /// one display attached; off means she stays put.
    var teleportEnabled = true {
        didSet { store(teleportEnabled, .teleport) }
    }
    var teleportCadence: TeleportCadence = .normal {
        didSet { store(teleportCadence.rawValue, .cadence) }
    }
    /// Which animals the desk should have, in order. The first one is Pookie
    /// unless `defaultCritter` says otherwise.
    var roster: [CritterConfig] = [.tabbyCat] {
        didSet { store(roster.map(\.encoded), .roster) }
    }
    /// Who answers when a producer talks to the colony.
    var defaultCritter: Int = 0 {
        didSet { store(defaultCritter, .spokespet) }
    }
    /// How many pets to start with, overriding the saved roster. `--pets N` sets
    /// it; nil means "whatever the roster says", which is the normal launch.
    var startPets: Int?
    /// Derived from `CatGeometry.stage`, so the window always contains the whole
    /// animal, tail and ears included, in every pose the renderer can draw, at
    /// every size setting.
    var petSize: CGSize {
        let base = CatGeometry.preferredWindowSize
        return CGSize(
            width: (base.width * petScale.factor).rounded(),
            height: (base.height * petScale.factor).rounded()
        )
    }
    /// Where to put her at launch. `--at x,y` sets this; nil means the usual
    /// bottom-right corner.
    var startOrigin: CGPoint?
    var verboseLogging = false

    private enum Key: String {
        case clickThrough = "clickThroughMode"
        case wander = "wanderEnabled"
        case followCursor = "followCursor"
        case perch = "perchEnabled"
        case jump = "jumpEnabled"
        case chatty = "chatty"
        case privacy = "hideFromScreenShare"
        case scale = "petScale"
        case teleport = "teleportEnabled"
        case cadence = "teleportCadence"
        case roster = "roster"
        case spokespet = "defaultCritter"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let raw = defaults.string(forKey: Key.clickThrough.rawValue),
           let mode = ClickThroughMode(rawValue: raw) {
            clickThroughMode = mode
        }
        wanderEnabled = defaults.bool(or: true, Key.wander.rawValue)
        followCursor = defaults.bool(or: true, Key.followCursor.rawValue)
        perchEnabled = defaults.bool(or: true, Key.perch.rawValue)
        jumpEnabled = defaults.bool(or: true, Key.jump.rawValue)
        chatty = defaults.bool(or: true, Key.chatty.rawValue)
        hideFromScreenShare = defaults.bool(or: false, Key.privacy.rawValue)
        if let raw = defaults.string(forKey: Key.scale.rawValue), let scale = CatScale(rawValue: raw) {
            petScale = scale
        }
        teleportEnabled = defaults.bool(or: true, Key.teleport.rawValue)
        if let raw = defaults.string(forKey: Key.cadence.rawValue),
           let cadence = TeleportCadence(rawValue: raw) {
            teleportCadence = cadence
        }
        if let raw = defaults.stringArray(forKey: Key.roster.rawValue) {
            let decoded = raw.compactMap(CritterConfig.init(encoded:))
            if !decoded.isEmpty { roster = decoded }
        }
        defaultCritter = min(max(defaults.integer(forKey: Key.spokespet.rawValue), 0), max(0, roster.count - 1))
    }
}

private extension UserDefaults {
    /// `bool(forKey:)` cannot tell "off" from "never set", and every one of these
    /// switches defaults to on.
    func bool(or fallback: Bool, _ key: String) -> Bool {
        object(forKey: key) == nil ? fallback : bool(forKey: key)
    }
}
