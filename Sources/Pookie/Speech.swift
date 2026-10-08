import CoreGraphics
import Foundation

/// How a bubble is painted. Styles are presentation only; the pet never parses
/// the text.
enum BubbleStyle: String, CaseIterable {
    case plain
    case info
    case warning
    case success
    case code
}

/// Everything the bubble window needs to draw, as a value.
struct BubbleContent: Equatable {
    var id: String
    var text: String
    var style: BubbleStyle
    /// A producer is still appending to this bubble.
    var streaming: Bool
    /// Motion-clock deadline. `.infinity` means sticky.
    var expiresAt: Double
}

/// What happened to an intent. Mirrors the ack vocabulary in `PROTOCOL.md`, so
/// the M3 server can translate one into the other without re-deciding anything.
enum SpeechOutcome: Equatable {
    case started
    case replaced
    case rateLimited(retryAfter: Double)
    case rejected(String)
}

/// The `say` / `bubble.show` / `bubble.append` / `bubble.hide` verbs, in-process.
///
/// Three design rules live here rather than in taste:
///
/// 1. **Silence by default.** Nothing is shown unless a producer asked.
/// 2. **One bubble at a time.** A new utterance replaces the current one, it
///    does not stack next to it.
/// 3. **Rate limited.** A bubble younger than `minimumGap` refuses to be
///    replaced, so a chatty producer cannot strobe the screen — and *each
///    producer* has its own budget on top of that, so one chatty app cannot
///    monopolise a pet that three apps are talking to.
///
/// M3 will decode the wire protocol into these calls; the M5 brain is just
/// another producer calling `say`. Nothing here knows about AppKit.
final class SpeechEngine {
    private(set) var bubble: BubbleContent?
    /// Bumped whenever the visible content changes, so the window can redraw
    /// only then instead of on every frame it is moved.
    private(set) var revision = 0

    /// Minimum age before a visible bubble may be replaced.
    var minimumGap: Double = 1.2
    /// How many lines one producer may show in a `producerWindow`, and how long
    /// that window is. A per-producer budget rather than a global one: the point
    /// is that one noisy producer cannot use up the pet that everybody shares.
    var producerBudget: Int = 6
    var producerWindow: Double = 60
    /// The shortest gap between two lines from the *same* producer, so a single
    /// app cannot fill its budget in one burst.
    var producerGap: Double = 2.5

    /// Per-producer history: when each last spoke, and how many times in the
    /// window that has not expired yet.
    private struct ProducerState {
        var lastSpokeAt: Double = -.infinity
        var recent: [Double] = []
    }
    private var producers: [String: ProducerState] = [:]

    /// Who is asking. `pookie` is this pet's own reactions; anything else is a
    /// producer, and the name is what the budget is keyed on.
    static let ownProducer = "pookie"

    /// How many lines a producer has left in the current window, for the
    /// heartbeat and for tests.
    func remainingBudget(for producer: String, now: Double) -> Int {
        let state = producers[producer] ?? ProducerState()
        let live = state.recent.filter { now - $0 < producerWindow }
        return max(0, producerBudget - live.count)
    }
    /// Master switch. The menu item flips this to make her mute.
    var enabled = true

    private var lastShownAt: Double = -.infinity
    private var startedAt: Double = -.infinity
    private var counter = 0

    var isSpeaking: Bool { bubble != nil }

    /// Show a line. `duration` overrides the length-derived TTL; `sticky` keeps
    /// it up until something else replaces it.
    @discardableResult
    func say(
        _ text: String,
        style: BubbleStyle = .plain,
        duration: Double? = nil,
        streaming: Bool = false,
        sticky: Bool = false,
        from producer: String = SpeechEngine.ownProducer,
        now: Double
    ) -> SpeechOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rejected("empty_text") }
        guard enabled else { return .rejected("muted") }

        // This producer's own budget, before the shared gap: her own reactions are
        // exempt, because they are already governed by the behaviour that
        // triggers them and a pet that cannot sneeze because an app talked too
        // much is a bug.
        if producer != Self.ownProducer {
            var state = producers[producer] ?? ProducerState()
            state.recent = state.recent.filter { now - $0 < producerWindow }
            if now - state.lastSpokeAt < producerGap {
                return .rateLimited(retryAfter: producerGap - (now - state.lastSpokeAt))
            }
            if state.recent.count >= producerBudget {
                let oldest = state.recent.min() ?? now
                return .rateLimited(retryAfter: producerWindow - (now - oldest))
            }
            state.lastSpokeAt = now
            state.recent.append(now)
            producers[producer] = state
        }

        var outcome: SpeechOutcome = .started
        if let current = bubble {
            let age = now - startedAt
            if age < minimumGap {
                return .rateLimited(retryAfter: minimumGap - age)
            }
            // Streaming producers own their bubble; a fresh utterance retires it.
            _ = current
            outcome = .replaced
        }

        counter += 1
        let ttl = duration ?? Self.duration(for: trimmed)
        bubble = BubbleContent(
            id: "b\(counter)",
            text: trimmed,
            style: style,
            streaming: streaming,
            expiresAt: sticky ? .infinity : now + ttl
        )
        startedAt = now
        lastShownAt = now
        revision += 1
        return outcome
    }

    /// `bubble.append`: grow the open bubble. Refuses unknown ids rather than
    /// silently creating one, matching `PROTOCOL.md` §4.8.
    @discardableResult
    func append(_ delta: String, to id: String, final: Bool = false, now: Double) -> SpeechOutcome {
        guard var current = bubble else { return .rejected("unknown_bubble") }
        guard current.id == id else { return .rejected("unknown_bubble") }
        guard enabled else { return .rejected("muted") }

        current.text += delta
        current.streaming = !final
        if final {
            current.expiresAt = now + Self.duration(for: current.text)
        }
        bubble = current
        revision += 1
        return .started
    }

    /// `bubble.hide`. With no id, dismiss whatever is up.
    @discardableResult
    func hide(id: String? = nil, now: Double) -> Bool {
        guard let current = bubble else { return false }
        if let id, current.id != id { return false }
        bubble = nil
        startedAt = now
        revision += 1
        return true
    }

    /// Expire a bubble whose TTL has run out. Returns true if anything changed.
    @discardableResult
    func tick(now: Double) -> Bool {
        guard let current = bubble, now >= current.expiresAt else { return false }
        bubble = nil
        revision += 1
        return true
    }

    /// Reading speed, not a stopwatch: short lines should not linger, and a
    /// paragraph should not vanish mid-sentence.
    static func duration(for text: String) -> Double {
        let characters = Double(text.count)
        return min(9.0, max(2.0, 1.4 + characters * 0.06))
    }
}

/// The lines she says when *you* interact with her, as opposed to lines a
/// producer sent. Deliberately few and short: a pet that comments on everything
/// is the "annoying" failure mode the design is built to avoid, so these are
/// rate-limited by `SpeechEngine` like any other producer.
enum PetChatter {
    static func tapped() -> String {
        [
            "mrrp?",
            "purrr.",
            "hi!",
            "*blinks*",
            "that's my ear.",
            "again?",
        ].randomElement() ?? "mrrp?"
    }

    static func landed(hard: Bool) -> String {
        if hard {
            return ["oof.", "wheee!", "I meant to do that.", "*dusts self off*"].randomElement() ?? "oof."
        }
        return ["hm.", "down.", "*shakes tail*"].randomElement() ?? "hm."
    }

    static func perched(on owner: String) -> String {
        let name = owner.isEmpty ? "this window" : owner
        return [
            "nice ledge.",
            "I'll sit here.",
            "\(name) is mine now.",
            "good view.",
        ].randomElement() ?? "nice ledge."
    }

    /// A new pet arriving. Only ever said when the user asked for one.
    static func arrived() -> String {
        [
            "hi!",
            "mrrp!",
            "hello.",
            "*looks around*",
            "oh, a desk.",
        ].randomElement() ?? "mrrp!"
    }

    /// Taking a punch. Short, undignified, and never the same twice.
    static func hit() -> String {
        ["ow!", "!!", "eep!", "oof!", "mraow!", "*thud*"].randomElement() ?? "ow!"
    }

    /// A sneeze. Small, involuntary, and the only line she never means.
    static func sneeze() -> String {
        ["achoo!", "ha-choo!", "*achoo*"].randomElement() ?? "achoo!"
    }

    /// Mid-scrap. Short, indignant, and only ever one bubble between the two of
    /// them.
    static func scuffling() -> String {
        [
            "POW!",
            "*bap bap*",
            "mrrp!!",
            "biff!",
            "*thump*",
            "hey!!",
            "hsss!",
            "!!",
        ].randomElement() ?? "POW!"
    }

    /// Mid-chase. One line per bout, not one per cat: two bubbles at once is the
    /// noise the speech rules exist to prevent.
    static func playing() -> String {
        [
            "gotcha!",
            "mrrp!!",
            "*pounce*",
            "chase me!",
            "!",
        ].randomElement() ?? "mrrp!!"
    }
}
