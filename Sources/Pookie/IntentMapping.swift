import CoreGraphics

/// Intent arguments → the values the behaviour layer takes.
///
/// Pure, and separate from both the transport and the behaviour, because the two
/// things that go wrong here are silent: a **coordinate convention** (the protocol
/// speaks Core Graphics global display space, origin top-left and `y` increasing
/// *down*, while AppKit's screens are bottom-left) and an **anchor** that has to mean
/// something on a desk with two monitors of different heights. Both are testable
/// without a window server, so they are tested.
enum IntentMapping {

    // MARK: - Anchors

    /// The anchors in `PROTOCOL.md` §3.
    enum Anchor: String, CaseIterable {
        case bottomLeft = "bottom-left"
        case bottomRight = "bottom-right"
        case bottomCentre = "bottom-centre"
        case topLeft = "top-left"
        case topRight = "top-right"
        case centre
        case cursor
        case frontWindowEdge = "front-window-edge"
    }

    /// Where an anchor is on a given screen, in **Core Graphics** coordinates.
    ///
    /// The protocol's convention is the one `CGWindowListCopyWindowInfo` uses, which
    /// is what keeps producer code boring — so this is where the flip happens, once,
    /// rather than in every client.
    static func point(
        for anchor: Anchor,
        region: CGRect,
        displayHeight: CGFloat,
        petSize: CGSize,
        cursor: CGPoint? = nil
    ) -> CGPoint? {
        // The region arrives in AppKit's bottom-left space; the answer leaves in Core
        // Graphics' top-left space, whose origin is the top of the *display* — not the
        // top of the visible region. Flipping about the region instead is wrong by the
        // menu bar, which is a bug you would only notice by looking at where she went.
        let flip: (CGPoint) -> CGPoint = { point in
            CGPoint(x: point.x, y: displayHeight - point.y)
        }
        switch anchor {
        case .bottomLeft:
            return flip(CGPoint(x: region.minX + 8, y: region.minY + 8))
        case .bottomRight:
            return flip(CGPoint(x: region.maxX - petSize.width - 8, y: region.minY + 8))
        case .bottomCentre:
            return flip(CGPoint(x: region.midX - petSize.width / 2, y: region.minY + 8))
        case .topLeft:
            return flip(CGPoint(x: region.minX + 8, y: region.maxY - petSize.height - 8))
        case .topRight:
            return flip(CGPoint(
                x: region.maxX - petSize.width - 8,
                y: region.maxY - petSize.height - 8
            ))
        case .centre:
            return flip(CGPoint(
                x: region.midX - petSize.width / 2,
                y: region.midY - petSize.height / 2
            ))
        case .cursor:
            return cursor
        case .frontWindowEdge:
            // Resolved by the caller, which has the scanned platforms: a pure mapping
            // has no business knowing about other apps' windows. Nil here means "ask
            // somebody who does", not "impossible".
            return nil
        }
    }

    /// An absolute point from the protocol into AppKit's space, and back. The two
    /// conventions differ by a flip about the main display's height, so a client that
    /// says `y: 100` means a hundred points *down* from the top.
    static func toAppKit(_ point: CGPoint, mainDisplayHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: mainDisplayHeight - point.y)
    }

    static func toProtocolSpace(_ point: CGPoint, mainDisplayHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: mainDisplayHeight - point.y)
    }

    // MARK: - Emote

    /// The eight emotes in `PROTOCOL.md` §4.2, and what this renderer can honestly do
    /// with each.
    enum Emote: String, CaseIterable {
        case happy
        case sparkle
        case confused
        case sleepy
        case alarmed
        case love
        case sweat
        case question

        /// The mood it holds, when there is one.
        var mood: CatMood? {
            switch self {
            case .happy, .love: return .happy
            case .sleepy: return .sleepy
            case .alarmed: return .alarmed
            case .confused: return .curious
            // No mood of its own, and no effect on this renderer yet.
            case .sparkle, .sweat, .question: return nil
            }
        }

        var blushes: Bool { self == .love }

        /// The effect an emote draws around her head, if it has one.
        enum Effect: Equatable {
            case sparkle
            case sweat
        }

        var effect: Effect? {
            switch self {
            case .sparkle: return .sparkle
            case .sweat: return .sweat
            default: return nil
            }
        }

        /// `question` is a bubble, which the pet already has.
        var line: String? {
            self == .question ? "?" : nil
        }

        /// All eight are supported: six as a held mood, one as a bubble, two as an
        /// effect around her head.
        var isSupported: Bool { true }
    }

    // MARK: - State

    /// The six modes in `PROTOCOL.md` §4.6, as changes to the behaviour profile.
    enum StateName: String, CaseIterable {
        case idle
        case sleep
        case work
        case alert
        case hidden
        case celebrate
    }

    /// What a mode means to `PetMotion`.
    struct Profile: Equatable {
        var forcesSleep = false
        /// Off means she holds still: a working pet should not wander across the
        /// window you are typing in.
        var wanders = true
        /// On means she watches the cursor.
        var watchesCursor = true
        var mood: CatMood?
        var hides = false
        /// A celebration is a burst, not a mood: one zoomie when the mode starts.
        var celebrates = false
    }

    static func profile(for name: StateName) -> Profile {
        switch name {
        case .idle:
            return Profile()
        case .sleep:
            return Profile(forcesSleep: true, wanders: false, mood: .sleepy)
        case .work:
            // Present, still, and watching what you are doing.
            return Profile(wanders: false, watchesCursor: true)
        case .alert:
            return Profile(wanders: false, watchesCursor: true, mood: .alarmed)
        case .hidden:
            return Profile(wanders: false, watchesCursor: false, hides: true)
        case .celebrate:
            return Profile(wanders: true, mood: .happy, celebrates: true)
        }
    }
}
