import AppKit

// Headless modes first: they must not require a window server session.
let arguments = CommandLine.arguments

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    Pookie — a desktop cat that lives on your screen.

    Usage:
      Pookie                       run the pet
      Pookie --say "text"          make a running Pookie say something, then exit
      Pookie --render-png <path>   write a pose sheet to a PNG and exit
      Pookie --render-species <p>  write a species sheet to a PNG and exit
      Pookie --render-patterns <p> write a markings sheet to a PNG and exit
      Pookie --selftest            run headless checks and exit
      Pookie --windows             list the windows she can perch on, then exit
      Pookie --verbose             log window and interaction details to stderr
      Pookie --at <x,y>            start at a specific screen position
      Pookie --no-wander           do not wander (clean CPU measurements)
      Pookie --no-perch            do not sit on other apps' windows
      Pookie --no-jump             do not jump up onto windows by herself
      Pookie --no-teleport         do not blink between displays
      Pookie --scale <name>        small | medium | large | huge
      Pookie --pets <n>            start with n cats (1...\(PetCohort.maximumPets))
      Pookie --mute                do not react to being petted

    Global hotkeys (no Accessibility permission required):
      control-option-H   show / hide Pookie
      control-option-P   cycle mouse mode (click-through gaps / capture box / ignore)
      control-option-R   bring Pookie home
      control-option-D   describe current state to stderr
      control-option-T   say hello (test the speech bubble)
      control-option-M   mute / unmute reactions
    """)
    exit(0)
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
if let index = arguments.firstIndex(of: "--say") {
    let text = index + 1 < arguments.count ? arguments[index + 1] : "hello"
    DistributedNotificationCenter.default().postNotificationName(
        AppDelegate.sayNotification,
        object: nil,
        userInfo: ["text": text],
        deliverImmediately: true
    )
    print("pookie says: \(text)")
    exit(0)
}

// Interactive mode.
let delegate = AppDelegate()
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
