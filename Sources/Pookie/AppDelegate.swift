import AppKit
import ServiceManagement

/// Pookie runs as an `.accessory` app: no Dock icon, no menu bar of its own.
/// The status item is the only UI, because a pet you cannot easily quit is a
/// pet you will resent.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The `pookie say "hi"` bridge. A distributed notification is the
    /// permission-free way for another process to reach a running pet; it is a
    /// stand-in for the M3 loopback socket protocol, and the shape of the call
    /// (`cohort.say`) is the same either way.
    static let sayNotification = AppIdentity.current.sayNotification

    /// The preemption stack: what is running, what is waiting, and which of them a new
    /// intent replaces (`PROTOCOL.md` §5).
    ///
    /// Until this existed, `priority` was parsed, clamped, stored and never read — a
    /// producer asking for 90 was treated exactly like one asking for 0, which made
    /// §5's whole table decorative.
    var actionStack = ActionStack()
    var updateController: UpdateController?
    var cohort: PetCohort?
    var settingsWindow: SettingsWindowController?
    var controlServer: ControlServer?
    /// Sleep, wake, lock and unlock. Removed in `applicationWillTerminate`.
    var pauseObservers: [NSObjectProtocol] = []
    var statusItem: NSStatusItem?
    var hotKeys: [GlobalHotKey] = []
    var sayObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.verbose = AppConfig.shared.verboseLogging
        let colony = PetCohort()
        colony.contextMenuBuilder = { [weak self] pet in self?.petMenu(for: pet) }
        cohort = colony
        // The collection loads: everything the roster says belongs on the desk,
        // in order, up to the cap. `--pets N` overrides the headcount for one run
        // without touching the roster.
        colony.spawnFromRoster()

        if AppConfig.shared.openSettingsAtLaunch {
            openSettings()
        }

        // First run: say the one thing a new user cannot guess. Once, and never
        // again — a pet that explains itself every launch is a nag.
        if !AppConfig.shared.hasOnboarded {
            AppConfig.shared.hasOnboarded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.cohort?.say("psst — \(AppIdentity.current.shortcutPrefix)-H hides me. Right-click me for the rest.")
            }
        }
        updateController = UpdateController()
        installStatusItem()
        installHotKeys()
        installSayBridge()
        installPauseObservers()
        installControlServer()
    }

    deinit { cleanUp() }

    func applicationWillTerminate(_ notification: Notification) {
        cleanUp()
    }

    private func cleanUp() {
        if let sayObserver {
            DistributedNotificationCenter.default().removeObserver(sayObserver)
            self.sayObserver = nil
        }
        for token in pauseObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            DistributedNotificationCenter.default().removeObserver(token)
        }
        pauseObservers.removeAll()
        hotKeys.removeAll()
        // Termination does not guarantee delegate deallocation before exit.
        controlServer?.stop()
        controlServer = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Pause everything while the screen is locked or the machine is asleep.
    ///
    /// Two sources, because macOS splits them: `NSWorkspace` knows about sleep, and
    /// the screen lock is a distributed notification. Both are permission-free —
    /// observing is not capturing, and neither needs Accessibility or Screen
    /// Recording. `Pookie --simulate-lock on` posts the same notification, which is
    /// how the wiring is exercised without locking a real screen.
    func installPauseObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        pauseObservers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.cohort?.setSystemPaused(true)
        })
        pauseObservers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.cohort?.setSystemPaused(false)
        })

        let distributed = DistributedNotificationCenter.default()
        for name in [Self.screenLockedNotification, Self.screenUnlockedNotification] {
            let paused = name == Self.screenLockedNotification
            pauseObservers.append(distributed.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                self?.cohort?.setSystemPaused(paused)
            })
        }
    }

    /// The names macOS posts when the screen locks and unlocks. They are not in a
    /// header; they are what every menu-bar app observes.
    static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
    static let screenUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")

    func installSayBridge() {
        sayObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.sayNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let text = note.userInfo?["text"] as? String else { return }
            let style = (note.userInfo?["style"] as? String).flatMap(BubbleStyle.init(rawValue:)) ?? .plain
            let producer = (note.userInfo?["producer"] as? String) ?? "unknown"
            let outcome = self?.cohort?.say(text, style: style, from: producer)
            // A refusal is invisible from the sender's side, so it is logged here:
            // "why did my script stop talking" has to have an answer.
            if case .rateLimited(let retryAfter) = outcome {
                Log.info("producer \(producer) rate limited for \(String(format: "%.1f", retryAfter))s")
            }
        }
    }

    // MARK: - Hot keys
    //
    // Carbon hot keys need no Accessibility permission, so these work on a
    // fresh machine with zero prompts.

    func installHotKeys() {
        let bindings: [(UInt32, String, Selector, String)] = [
            (KeyCode.h, "H", #selector(toggleVisibility), "hide/show"),
            (KeyCode.p, "P", #selector(cycleClickThrough), "cycle mouse mode"),
            (KeyCode.d, "D", #selector(describeState), "describe state"),
            (KeyCode.r, "R", #selector(resetPosition), "bring home"),
            (KeyCode.t, "T", #selector(sayHello), "say hello"),
            (KeyCode.m, "M", #selector(toggleChatty), "mute/unmute"),
        ]

        for (keyCode, key, selector, name) in bindings {
            guard let hotKey = GlobalHotKey(
                keyCode: keyCode,
                modifiers: AppIdentity.current.hotKeyModifiers,
                action: { [weak self] in _ = self?.perform(selector) }
            ) else { continue }
            hotKeys.append(hotKey)
            Log.info("bound \(AppIdentity.current.shortcutPrefix)-\(key) -> \(name)")
        }
    }

    /// Add or remove the login item, reporting rather than assuming. Shared by the
    /// settings checkbox and `--launch-at-login`, so both take the same path.
    @discardableResult
    static func setLaunchAtLogin(_ wanted: Bool) -> Bool {
        guard AppIdentity.current.allowsLoginItem else {
            print("launch at login is disabled in \(AppIdentity.current.displayName)")
            return false
        }
        do {
            if wanted {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            AppConfig.shared.launchAtLogin = wanted
            print("launch at login: \(wanted ? "on" : "off") (\(SMAppService.mainApp.status == .enabled ? "enabled" : "not enabled"))")
            return true
        } catch {
            print("launch at login refused: \(error.localizedDescription)")
            return false
        }
    }

}
