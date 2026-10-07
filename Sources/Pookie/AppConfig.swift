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

/// A single mutable settings object for M0. M8 replaces this with a real
/// preferences store; keeping it in one place now means nothing else has to
/// know how settings are persisted.
final class AppConfig {
    static let shared = AppConfig()

    var clickThroughMode: ClickThroughMode = .silhouette
    var wanderEnabled = true
    var followCursor = true
    /// Land on the top edges of other apps' windows instead of falling past
    /// them. Permission-free (`CGWindowList` geometry only) and switchable,
    /// because "the cat sits on my window" is charming and "the cat sits on my
    /// window during a demo" is not.
    var perchEnabled = true
    /// Jump up onto a reachable window top by herself, rather than only perching
    /// when you drop her there. Separate from `perchEnabled` because a pet that
    /// leaps around unprompted is charming right up until it is not.
    var jumpEnabled = true
    /// React to being petted, thrown, and perched on. Off means she only speaks
    /// when a producer tells her to.
    var chatty = true
    /// `NSWindow.sharingType = .none` hides the pet from screen sharing and
    /// captures. Deliberately off by default so screenshots still show Pookie.
    var hideFromScreenShare = false
    var palette: CatPalette = .tabby
    /// How big she is drawn. See `CatScale`.
    var petScale: CatScale = .medium
    /// How many pets to start with. The menu adds and removes them from there;
    /// this is what `--pets N` sets.
    var startPets: Int = 1
    /// Blink to another display every minute or so. Only does anything with
    /// more than one display attached; off means she stays put.
    var teleportEnabled = true
    /// Derived from `CatGeometry.stage`, so the window always contains the whole
    /// cat, tail and ears included, in every pose the renderer can draw, at
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

    private init() {}
}
