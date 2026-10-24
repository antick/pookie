import AppKit

// Headless modes first: they must not require a window server session.
let arguments = CommandLine.arguments

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    Pookie — a desktop cat that lives on your screen.

    Usage:
      Pookie                       run the pet
      pookie say "text"            drive a running Pookie (see `pookie help`)
      Pookie --say "text"          the flag-style equivalent, kept for scripts
      Pookie --producer <name>     name the sender, for the per-producer budget
      Pookie --simulate-lock <on|off>  post the screen-lock notification, to test the pause path
      Pookie --launch-at-login <on|off>  add or remove Pookie from your login items
      Pookie --render-icon <png>   export a 1024x1024 app icon and exit
      Pookie --icon-channel <c>    production | development (icon export only)
      Pookie --render-png <path>   write a pose sheet to a PNG and exit
      Pookie --render-species <p>  write a species sheet to a PNG and exit
      Pookie --render-patterns <p> write a markings sheet to a PNG and exit
      Pookie --render-brawl <p>    write a brawl sheet to a PNG and exit
      Pookie --settings            open the settings window at launch
      Pookie --selftest            run headless checks and exit
      Pookie --windows             list the windows she can perch on, then exit
      Pookie --verbose             log window and interaction details to stderr
      Pookie --at <x,y>            start at a specific screen position
      Pookie --no-wander           do not wander (clean CPU measurements)
      Pookie --no-perch            do not sit on other apps' windows
      Pookie --no-jump             do not jump up onto windows by herself
      Pookie --no-teleport         do not blink between displays
      Pookie --scale <name>        small | medium | large | huge
      Pookie --pets <n>            start with n pookies (1...\(PetCohort.maximumPets))
      Pookie --mute                do not react to being petted

    Global hotkeys (no Accessibility permission required):
      \(AppIdentity.current.shortcutPrefix)-H   show / hide Pookie
      \(AppIdentity.current.shortcutPrefix)-P   cycle mouse mode (click-through gaps / capture box / ignore)
      \(AppIdentity.current.shortcutPrefix)-R   bring Pookie home
      \(AppIdentity.current.shortcutPrefix)-D   describe current state to stderr
      \(AppIdentity.current.shortcutPrefix)-T   say hello (test the speech bubble)
      \(AppIdentity.current.shortcutPrefix)-M   mute / unmute reactions
    """)
    exit(0)
}

do {
    if let icon = try IconExportRequest.parse(arguments: arguments) {
        try AppIcon.export(to: icon.path, identity: icon.identity)
        print("wrote 1024x1024 \(icon.identity.displayName) icon to \(icon.path)")
        exit(0)
    }
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(2)
}

if arguments.contains("--verbose") {
    AppConfig.shared.verboseLogging = true
    Log.verbose = true
}

// A launch flag is an override for one run, not an edit to the saved settings:
// without this, `--no-wander` switches wandering off for good.
let overridesSettings = ["--no-wander", "--no-perch", "--no-jump", "--no-teleport", "--scale", "--at"]
    .contains { arguments.contains($0) }
if overridesSettings {
    AppConfig.shared.persistsChanges = false
}

// Open the settings window at launch, which is how it gets tested and
// screenshotted without a human clicking the menu bar.
if arguments.contains("--settings") {
    AppConfig.shared.openSettingsAtLaunch = true
}

// Useful for taking a clean energy reading without the cat ambling around.
if arguments.contains("--no-wander") {
    AppConfig.shared.wanderEnabled = false
}

if arguments.contains("--no-perch") {
    AppConfig.shared.perchEnabled = false
}

if arguments.contains("--no-jump") {
    AppConfig.shared.jumpEnabled = false
}

if arguments.contains("--no-teleport") {
    AppConfig.shared.teleportEnabled = false
}

if let index = arguments.firstIndex(of: "--scale") {
    let value = index + 1 < arguments.count ? arguments[index + 1] : ""
    guard let scale = CatScale(rawValue: value.lowercased()) else {
        FileHandle.standardError.write(Data("--scale expects small, medium, large or huge\n".utf8))
        exit(2)
    }
    AppConfig.shared.petScale = scale
}

if let index = arguments.firstIndex(of: "--pets") {
    let value = index + 1 < arguments.count ? arguments[index + 1] : ""
    guard let count = Int(value), count >= 1, count <= PetCohort.maximumPets else {
        FileHandle.standardError.write(Data("--pets expects 1...\(PetCohort.maximumPets)\n".utf8))
        exit(2)
    }
    AppConfig.shared.startPets = count
}

if arguments.contains("--mute") {
    AppConfig.shared.chatty = false
}

if arguments.contains("--selftest") {
    exit(Diagnostics.runSelfTest())
}

// What can she stand on right now? Geometry only, no permissions.
if arguments.contains("--windows") {
    exit(Diagnostics.listPlatforms())
}

if let index = arguments.firstIndex(of: "--at") {
    let value = index + 1 < arguments.count ? arguments[index + 1] : ""
    let parts = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    if parts.count == 2 {
        AppConfig.shared.startOrigin = CGPoint(x: parts[0], y: parts[1])
    } else {
        FileHandle.standardError.write(Data("--at expects x,y\n".utf8))
        exit(2)
    }
}

if let index = arguments.firstIndex(of: "--render-brawl") {
    let path = index + 1 < arguments.count ? arguments[index + 1] : "pookie-brawl.png"
    exit(Diagnostics.renderBrawlPNG(to: path))
}

if let index = arguments.firstIndex(of: "--render-patterns") {
    let path = index + 1 < arguments.count ? arguments[index + 1] : "pookie-patterns.png"
    exit(Diagnostics.renderPatternsPNG(to: path))
}

if let index = arguments.firstIndex(of: "--render-species") {
    let path = index + 1 < arguments.count ? arguments[index + 1] : "pookie-species.png"
    exit(Diagnostics.renderSpeciesPNG(to: path))
}

if let index = arguments.firstIndex(of: "--render-png") {
    let path = index + 1 < arguments.count ? arguments[index + 1] : "pookie-poses.png"
    exit(Diagnostics.renderPNG(to: path))
}

// `pookie say "hi"`: reach the running pet without Accessibility permission or
// a socket, by posting a distributed notification. This is the stand-in for the
// M3 loopback control plane; the receiving end calls the same
// `PetWindowController.say(_:)` the real protocol will.
// Unlike every other flag, this one changes the system: it adds or removes Pookie
// from your login items. It is a flag rather than only a checkbox so the same code
// path can be exercised from a script.
if let index = arguments.firstIndex(of: "--launch-at-login") {
    let wanted = index + 1 < arguments.count ? arguments[index + 1] : "on"
    exit(AppDelegate.setLaunchAtLogin(wanted == "on" || wanted == "1") ? 0 : 1)
}

// Posts the same notification macOS posts when the screen locks, so the pause path
// can be exercised without locking a real screen.
if let index = arguments.firstIndex(of: "--simulate-lock") {
    let on = index + 1 < arguments.count ? arguments[index + 1] : "on"
    let locked = on == "on" || on == "1"
    DistributedNotificationCenter.default().postNotificationName(
        locked ? AppDelegate.screenLockedNotification : AppDelegate.screenUnlockedNotification,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    print("simulated screen \(locked ? "lock" : "unlock")")
    exit(0)
}

// `pookie <verb>` — the command line the protocol's M3 criterion names. It goes
// through the control socket and prints the pet's ack, so a shell sees what happened
// rather than hoping.
// `pookie help` — the usage line advertises it, so it has to exist. Without this it
// fell through to the interactive path and started a pet, which is a memorable way to
// answer "how do I use this?".
if arguments.count >= 2, arguments[1] == "help" || arguments[1] == "--help" {
    print(CLI.usage)
    exit(0)
}

// `pookie events`: subscribe to everything and print it. A debugging tool, and the
// only way to watch a real click arrive.
if CLI.localVerb(for: arguments) == .events {
    guard let client = try? ControlClient() else {
        FileHandle.standardError.write(Data("pookie: no pet is listening. Is Pookie running?\n".utf8))
        exit(2)
    }
    client.send("{\"verb\":\"hello\",\"args\":{\"client\":\"pookie-cli/0.1\",\"protocol\":\"0.1\",\"events\":[\"*\"]}}")
    guard let greeting = client.readLine(timeout: 2), greeting.contains("hello.ok") else {
        client.close()
        FileHandle.standardError.write(Data("pookie: the pet did not answer the handshake\n".utf8))
        exit(2)
    }
    client.send("{\"id\":\"\(UUID().uuidString)\",\"ts\":\(Int(Date().timeIntervalSince1970 * 1000)),\"verb\":\"pet.on\",\"args\":{\"event\":[\"*\"],\"handler\":\"pookie-cli\"}}")
    while let line = client.readLine(timeout: 3600) {
        print(line)
        fflush(stdout)
    }
    client.close()
    exit(0)
}

if let command = CLI.command(for: arguments) {
guard let client = try? ControlClient() else {
    FileHandle.standardError.write(Data("pookie: no pet is listening. Is Pookie running?\n".utf8))
    exit(2)
}
client.send("{\"verb\":\"hello\",\"args\":{\"client\":\"pookie-cli/0.1\",\"protocol\":\"0.1\"}}")
guard let greeting = client.readLine(timeout: 2), greeting.contains("hello.ok") else {
    client.close()
    FileHandle.standardError.write(Data("pookie: connected, but the pet did not answer the handshake\n".utf8))
    exit(2)
}
client.send(CLI.line(for: command))
guard let ack = client.readLine(timeout: 3) else {
    client.close()
    FileHandle.standardError.write(Data("pookie: the pet said nothing back\n".utf8))
    exit(2)
}
client.close()
print(ack)
// A refusal is a non-zero exit, so a script can branch on it.
exit(ack.contains("\"ok\":true") ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--say") {
    let text = index + 1 < arguments.count ? arguments[index + 1] : "hello"
    // Who is asking. The protocol has no sender identity of its own yet, so the
    // producer names itself — `--producer` if given, else the environment, else
    // "cli". This is what the per-producer budget is keyed on, and it is why one
    // chatty script cannot use up a pet that three scripts are talking to.
    var producer = "cli"
    if let index = arguments.firstIndex(of: "--producer"), index + 1 < arguments.count {
        producer = arguments[index + 1]
    } else if let named = ProcessInfo.processInfo.environment["POOKIE_PRODUCER"], !named.isEmpty {
        producer = named
    }
// The control socket first — that is M3's transport, and it carries an ack. The
    // distributed notification is the stand-in it replaces, kept as a fallback so an
    // older running pet still answers.
    let intent = """
    {"id":"\(UUID().uuidString)","ts":\(Int(Date().timeIntervalSince1970 * 1000)),\
    "verb":"say","args":{"text":\(jsonString(text)),"producer":\(jsonString(producer))}}
    """.replacingOccurrences(of: "\n", with: "")
    if let client = try? ControlClient() {
        // The handshake first: acks are opt-in, and a client that never says hello is
        // assumed to want neither acks nor events — so skipping this gets a pet that
        // does exactly as it is told and says nothing about it.
        client.send(#"{"verb":"hello","args":{"client":"pookie-cli/0.1","protocol":"0.1"}}"#)
        guard let greeting = client.readLine(timeout: 2), greeting.contains("hello.ok") else {
            client.close()
            print("pookie: connected but the pet did not answer the handshake")
            exit(1)
        }
        client.send(intent)
        if let ack = client.readLine(timeout: 2) {
            print("pookie says: \(text) (from \(producer)) — \(ack)")
            client.close()
            exit(ack.contains("\"ok\":true") ? 0 : 1)
        }
        client.close()
        print("pookie: the control socket accepted the line but said nothing back")
        exit(1)
    }

    DistributedNotificationCenter.default().postNotificationName(
        AppDelegate.sayNotification,
        object: nil,
        userInfo: ["text": text, "producer": producer],
        deliverImmediately: true
    )
    print("pookie says: \(text) (from \(producer), over the notification fallback)")
    exit(0)
}

/// One JSON string literal, escaped. A text argument comes from a shell and can
/// contain anything, including the quote that would otherwise break the line.
func jsonString(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
}

// Interactive mode.
let delegate = AppDelegate()
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
