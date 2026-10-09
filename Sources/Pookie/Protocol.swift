import Foundation

/// The intent protocol's envelope, with no transport and no window server.
///
/// `docs/PROTOCOL.md` is the specification; this is the part of it that can be
/// decided without a socket and without a pet: decode a line, check it, dedupe it,
/// expire it, and answer with an ack. M3's transport will feed lines into
/// `IntentRouter.receive` and write the returned ack back down the connection —
/// which means the rules that are easy to get wrong (dedupe, TTL, error codes) are
/// testable headlessly, the way the behaviour layer is.
///
/// Everything here is pure: no AppKit, no I/O, no clock of its own. `now` is passed
/// in, so a test can expire an intent without waiting.

/// A verb from the vocabulary in `PROTOCOL.md` §4.
enum IntentVerb: String, CaseIterable {
    case say
    case emote
    case moveTo
    case lookAt
    case face
    case state
    /// The pet itself, not its bubble. M3's acceptance criteria name `pookie hide`
    /// and `pookie show`; §4 of the protocol defined `bubble.hide` and not these, so
    /// they are added here and documented in the same change.
    case hide
    case show
    case bubbleShow = "bubble.show"
    case bubbleAppend = "bubble.append"
    case bubbleHide = "bubble.hide"
    case spawn
    case despawn
    case petOn = "pet.on"

    /// The default priority and TTL from the specification, per verb.
    var defaults: (priority: Int, ttl: Double) {
        switch self {
        case .say: return (60, 15_000)
        case .emote: return (30, 4_000)
        case .moveTo: return (40, 10_000)
        case .lookAt: return (20, 5_000)
        case .face: return (20, 10_000)
        case .state: return (50, 30_000)
        // Above `say`, so hiding always wins — the same reasoning as `bubble.hide`.
        case .hide: return (90, 5_000)
        case .show: return (90, 5_000)
        case .bubbleShow: return (35, 20_000)
        case .bubbleAppend: return (55, 20_000)
        case .bubbleHide: return (65, 5_000)
        case .spawn: return (75, 10_000)
        case .despawn: return (75, 10_000)
        case .petOn: return (10, .infinity)
        }
    }
}

/// One decoded intent.
struct Intent: Equatable {
    var id: String
    /// Unix epoch milliseconds, as the producer stamped it.
    var ts: Double
    var verb: IntentVerb
    var args: [String: Any]
    var priority: Int
    var ttl: Double
    var pet: String?

    static func == (lhs: Intent, rhs: Intent) -> Bool {
        lhs.id == rhs.id && lhs.ts == rhs.ts && lhs.verb == rhs.verb
            && lhs.priority == rhs.priority && lhs.ttl == rhs.ttl && lhs.pet == rhs.pet
            && NSDictionary(dictionary: lhs.args) == NSDictionary(dictionary: rhs.args)
    }
}

/// What the pet answers with. `PROTOCOL.md` §2, "Acks".
struct IntentAck: Equatable {
    var id: String
    var ok: Bool
    /// `started`, `queued` or `dropped`, when the intent was accepted.
    var accepted: String?
    var error: String?
    var retryAfterMs: Double?
    var etaMs: Double?

    /// The error codes, so a typo cannot invent a new one.
    enum Error: String {
        case malformedJSON = "malformed_json"
        case missingField = "missing_field"
        case unknownVerb = "unknown_verb"
        case badArgs = "bad_args"
        case expired
        case duplicateID = "duplicate_id"
        case rateLimited = "rate_limited"
        case unknownPet = "unknown_pet"
        case capacity
        case unsupported
    }

    static func refused(_ id: String, _ error: Error) -> IntentAck {
        IntentAck(id: id, ok: false, accepted: "dropped", error: error.rawValue)
    }

    static func started(_ id: String) -> IntentAck {
        IntentAck(id: id, ok: true, accepted: "started", error: nil, etaMs: 0)
    }

    /// One NDJSON line, which is what goes back down the socket.
    var line: String {
        var fields: [String] = ["\"id\":\"\(id)\"", "\"ok\":\(ok)"]
        if let accepted { fields.append("\"accepted\":\"\(accepted)\"") }
        if let error { fields.append("\"error\":\"\(error)\"") }
        if let retryAfterMs { fields.append("\"retry_after_ms\":\(Int(retryAfterMs))") }
        if let etaMs { fields.append("\"eta_ms\":\(Int(etaMs))") }
        return "{" + fields.joined(separator: ",") + "}"
    }
}

/// The envelope rules: decode, validate, dedupe, expire.
final class IntentRouter {
    /// Ids already seen, oldest first. Dedupe is by `id` and makes retries safe, so
    /// the memory has to be bounded — a producer that retries forever must not grow
    /// it forever.
    private var seen: [String] = []
    private var seenSet: Set<String> = []
    var dedupeMemory = 512

    /// How many intents have been accepted and how many refused, for the log line
    /// and the selftest.
    private(set) var acceptedCount = 0
    private(set) var refusedCount = 0

    /// Decode one line and answer it. `now` is the same clock the producer stamps
    /// with, in epoch milliseconds.
    func receive(line: String, now: Double) -> IntentAck {
        receiveResult(line: line, now: now).ack
    }

    /// The same thing, with the decoded intent when there is one — which is what the
    /// transport needs in order to hand it to the behaviour layer.
    func receiveResult(line: String, now: Double) -> (ack: IntentAck, intent: Intent?) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            refusedCount += 1
            return (.refused("", .malformedJSON), nil)
        }

        guard let id = object["id"] as? String, !id.isEmpty else {
            refusedCount += 1
            return (.refused("", .missingField), nil)
        }
        guard let ts = object["ts"] as? Double ?? (object["ts"] as? Int).map(Double.init) else {
            refusedCount += 1
            return (.refused(id, .missingField), nil)
        }
        guard let verbName = object["verb"] as? String else {
            refusedCount += 1
            return (.refused(id, .missingField), nil)
        }
        guard let verb = IntentVerb(rawValue: verbName) else {
            refusedCount += 1
            return (.refused(id, .unknownVerb), nil)
        }
        // `args` is required and must not be null: the specification is explicit,
        // and a missing object is the difference between "no arguments" and "the
        // producer forgot".
        guard let args = object["args"] as? [String: Any] else {
            refusedCount += 1
            return (.refused(id, .missingField), nil)
        }

        // Dedupe before expiry: a retry of something that already ran is a
        // duplicate, not a stale intent, and saying so is more useful.
        if seenSet.contains(id) {
            refusedCount += 1
            return (.refused(id, .duplicateID), nil)
        }

        let defaults = verb.defaults
        let ttl = (object["ttl"] as? Double) ?? (object["ttl"] as? Int).map(Double.init) ?? defaults.ttl
        // A TTL of infinity is the subscription case (`pet.on`): never expires.
        if ttl.isFinite, ts + ttl < now {
            refusedCount += 1
            return (.refused(id, .expired), nil)
        }

        var priority = defaults.priority
        if let raw = (object["priority"] as? Double) ?? (object["priority"] as? Int).map(Double.init) {
            // The range is the specification's; a producer that sends 900 gets the
            // ceiling rather than an error, because the alternative is a pet that
            // refuses to speak over a number nobody can see.
            priority = min(100, max(0, Int(raw)))
        }

        let intent = Intent(
            id: id,
            ts: ts,
            verb: verb,
            args: args,
            priority: priority,
            ttl: ttl,
            pet: object["pet"] as? String
        )
        remember(id)
        acceptedCount += 1
        return (.started(intent.id), intent)
    }

    private func remember(_ id: String) {
        seen.append(id)
        seenSet.insert(id)
        while seen.count > dedupeMemory {
            let oldest = seen.removeFirst()
            seenSet.remove(oldest)
        }
    }
}
