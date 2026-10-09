import Foundation

/// The `pookie` command line, as a pure argument parser.
///
/// `PROTOCOL.md`'s M3 criterion is `pookie say "hi"` from a fresh terminal, which
/// means the command line is a first-class surface rather than a set of debug flags.
/// Parsing is separated from sending so the verbs can be tested without a socket, and
/// so a mistake in them is a failing check rather than a confusing refusal from a
/// running pet.
enum CLI {
    /// One parsed command: the verb and its arguments, ready to become an intent.
    struct Command: Equatable {
        var verb: IntentVerb
        var args: [String: Any]

        static func == (lhs: Command, rhs: Command) -> Bool {
            lhs.verb == rhs.verb && NSDictionary(dictionary: lhs.args) == NSDictionary(dictionary: rhs.args)
        }
    }

    /// The usage line, which is also the list of verbs a client can rely on.
    static let usage = """
    usage: pookie <verb> [args]

      pookie say "text"          say something (--producer <name> names the sender)
      pookie emote <name>        happy | love | confused | sleepy | alarmed | question
      pookie move <anchor>       bottom-left | bottom-right | bottom-centre | top-left |
                                 top-right | centre | cursor
      pookie move <x> <y>        absolute position, in the protocol's coordinates
      pookie face <direction>    left | right | cursor
      pookie state <name>        idle | sleep | work | alert | hidden | celebrate
      pookie hide | show         hide or show the pet
    """

    /// Parse `pookie <verb> [args]`.
    ///
    /// Returns nil when the arguments are not a command, so the caller can fall back
    /// to the flag-style surface (`--say`, `--selftest`, …) that predates it.
    static func command(for arguments: [String]) -> Command? {
        guard arguments.count >= 2 else { return nil }
        let verb = arguments[1]
        guard !verb.hasPrefix("-") else { return nil }
        let rest = Array(arguments.dropFirst(2))

        switch verb {
        case "say":
            let text = rest.filter { !$0.hasPrefix("--") }.joined(separator: " ")
            guard !text.isEmpty else { return nil }
            var args: [String: Any] = ["text": text]
            if let index = rest.firstIndex(of: "--producer"), index + 1 < rest.count {
                args["producer"] = rest[index + 1]
            }
            return Command(verb: .say, args: args)

        case "emote":
            guard let name = rest.first else { return nil }
            return Command(verb: .emote, args: ["name": name])

        case "move":
            guard let first = rest.first else { return nil }
            if let x = Double(first), rest.count >= 2, let y = Double(rest[1]) {
                return Command(verb: .moveTo, args: ["x": x, "y": y])
            }
            return Command(verb: .moveTo, args: ["anchor": first])

        case "face":
            guard let direction = rest.first else { return nil }
            var args: [String: Any] = ["direction": direction]
            if let index = rest.firstIndex(of: "--hold-ms"), index + 1 < rest.count,
               let hold = Double(rest[index + 1]) {
                args["holdMs"] = hold
            }
            return Command(verb: .face, args: args)

        case "state":
            guard let name = rest.first else { return nil }
            return Command(verb: .state, args: ["name": name])

        case "hide":
            return Command(verb: .hide, args: [:])

        case "show":
            return Command(verb: .show, args: [:])

        default:
            return nil
        }
    }

    /// The wire line for a command: one JSON object, `PROTOCOL.md` §2.
    static func line(for command: Command, id: String = UUID().uuidString, now: Date = Date()) -> String {
        let args = command.args
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\"\(key)\":\(json(value))"
            }
            .joined(separator: ",")
        let timestamp = Int(now.timeIntervalSince1970 * 1000)
        return "{\"id\":\"\(id)\",\"ts\":\(timestamp),\"verb\":\"\(command.verb.rawValue)\",\"args\":{\(args)}}"
    }

    /// A JSON value, escaped. An argument comes from a shell and can contain anything,
    /// including the quote that would otherwise break the line.
    static func json(_ value: Any) -> String {
        switch value {
        case let text as String:
            let escaped = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return "\"\(escaped)\""
        case let number as Double:
            return number == number.rounded() ? String(Int(number)) : String(number)
        case let flag as Bool:
            return flag ? "true" : "false"
        default:
            return "\"\""
        }
    }
}
