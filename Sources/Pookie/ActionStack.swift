import Foundation

/// The preemption stack from `PROTOCOL.md` §5.
///
/// Until now `priority` was parsed, clamped, stored and **never read**: a producer
/// asking for 90 was treated exactly like one asking for 0, which made §5's table
/// decorative. This is the machine that table describes, and it is pure — no pet, no
/// socket, no clock of its own — so the four normative rules can be tested directly
/// rather than inferred from behaviour.
///
/// The rules, in the specification's words:
///
/// 1. A strictly higher priority preempts the running action. **Equal priority never
///    preempts** — it queues.
/// 2. `drag` (100) clears the stack. Parked intents resume on `dropped` only if their
///    TTL has not expired.
/// 3. A running `say` holds a **locomotion lock**: `moveTo` and idle wander are
///    deferred, not dropped. `lookAt`, `face`, `emote`, blink, breathing and tail sway
///    still run, because they do not move the body root.
/// 4. Idle wandering must never interrupt a sentence — which falls out of rule 1,
///    since idle is priority 0.
struct ActionStack {
    /// What is running, and what is waiting behind it.
    struct Entry: Equatable {
        var intent: Intent
        var priority: Int
        var verb: IntentVerb
        /// When it started, or when it was parked.
        var at: Double
        /// When it finishes on its own. `.infinity` for a verb that completes at once,
        /// which is most of them — a mode is a setting, not a running action, and
        /// treating it as one would block everything below it forever.
        var deadline: Double = .infinity

        func hasFinished(now: Double) -> Bool { now >= deadline }

        /// When it expires, from the producer's own stamp. `.infinity` for a
        /// subscription, which has no TTL by design.
        var expiresAt: Double { intent.ttl.isFinite ? intent.ts + intent.ttl : .infinity }

        func hasExpired(now: Double) -> Bool { now > expiresAt }
    }

    /// What the pet should do with an intent it has just accepted.
    enum Decision: Equatable {
        /// Start it now. `preempted` names what it displaced, if anything.
        case started(preempted: IntentVerb?)
        /// Park it behind something more important.
        case queued(behind: IntentVerb)
        /// Refuse it, with a reason for the log.
        case dropped(reason: String)
    }

    private(set) var running: Entry?
    private(set) var waiting: [Entry] = []

    /// The priority `drag` carries: nothing preempts it, and it clears the stack.
    static let dragPriority = 100

    /// Whether an action, once started, holds the stack until it finishes on its own.
    ///
    /// Instant verbs (`hide`, `spawn`, `moveTo`) complete synchronously and free the
    /// stack immediately; the ones with a duration hold it, which is what makes rule 3
    /// mean anything.
    static func holds(verb: IntentVerb) -> Bool {
        switch verb {
        case .say, .bubbleShow, .emote, .lookAt, .face: return true
        default: return false
        }
    }

    /// Rule 3: while a sentence is running, anything that moves the body root waits.
    static func isLocomotion(_ verb: IntentVerb) -> Bool {
        verb == .moveTo
    }

    /// Finish a running action whose own duration has run out.
    ///
    /// Lazy rather than timer-driven: the stack is checked when something arrives, so
    /// there is no clock to keep in step with the pet's own. A `say` that finished two
    /// seconds ago is not still "running" when the next intent turns up.
    mutating func finishIfDue(now: Double) -> (next: Entry?, dropped: [Entry])? {
        guard let current = running, current.hasFinished(now: now) else { return nil }
        return finish(now: now)
    }

    /// Offer an intent to the stack.
    mutating func submit(_ entry: Entry, now: Double) -> Decision {
        _ = finishIfDue(now: now)

        // A stale intent is refused before it can displace anything.
        if entry.hasExpired(now: now) {
            return .dropped(reason: "expired")
        }

        guard let current = running else {
            running = entry
            return .started(preempted: nil)
        }

        // Rule 3, which the priority table alone does not express: a move waits behind
        // a sentence even though both are "running" verbs, because a sentence that
        // walks away mid-word is the thing the locomotion lock exists to prevent.
        if Self.holds(verb: current.verb), Self.isLocomotion(entry.verb) {
            waiting.append(entry)
            waiting.sort { $0.priority > $1.priority }
            return .queued(behind: current.verb)
        }

        // Rule 1: strictly higher preempts, equal queues.
        if entry.priority > current.priority {
            // Rule 2: `drag` clears the stack rather than parking what it displaces —
            // the user's hand outranks a queue, and a parked intent resumes only on
            // `dropped`, which is the drag ending.
            if current.priority >= Self.dragPriority {
                return .queued(behind: current.verb)
            }
            running = entry
            return .started(preempted: current.verb)
        }

        waiting.append(entry)
        waiting.sort { $0.priority > $1.priority }
        return .queued(behind: current.verb)
    }

    /// The running action finished. Returns the next one to start, if any — and drops
    /// anything that went stale while it waited (criterion 5: TTL is evaluated at
    /// *dispatch*, not only at arrival).
    mutating func finish(now: Double) -> (next: Entry?, dropped: [Entry]) {
        running = nil
        var dropped: [Entry] = []
        while let next = waiting.first {
            waiting.removeFirst()
            if next.hasExpired(now: now) {
                dropped.append(next)
                continue
            }
            running = next
            return (next, dropped)
        }
        return (nil, dropped)
    }

    /// The user picked the pet up: `drag` clears the stack, and what was running is
    /// parked to resume when it is dropped.
    mutating func beginDrag(_ entry: Entry) {
        if let current = running { waiting.append(current) }
        running = entry
    }

    /// The drag ended: resume the most important thing that has not expired.
    mutating func endDrag(now: Double) -> (next: Entry?, dropped: [Entry]) {
        running = nil
        waiting.sort { $0.priority > $1.priority }
        return finish(now: now)
    }

    var isEmpty: Bool { running == nil && waiting.isEmpty }
}
