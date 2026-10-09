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
    static let sayNotification = Notification.Name("com.pookie.pet.say")

    private var cohort: PetCohort?
    private var settingsWindow: SettingsWindowController?
    private var controlServer: ControlServer?
    /// Sleep, wake, lock and unlock. Removed in `applicationWillTerminate`.
    private var pauseObservers: [NSObjectProtocol] = []
    private var statusItem: NSStatusItem?
    private var hotKeys: [GlobalHotKey] = []
    private var sayObserver: NSObjectProtocol?

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
                self?.cohort?.say("psst — control-option-H hides me. Right-click me for the rest.")
            }
        }
        installStatusItem()
        installHotKeys()
        installSayBridge()
        installPauseObservers()
        installControlServer()
    }

    deinit {
        if let sayObserver {
            DistributedNotificationCenter.default().removeObserver(sayObserver)
        for token in pauseObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            DistributedNotificationCenter.default().removeObserver(token)
        }
        pauseObservers.removeAll()
        // The socket is removed on the way out, so the next launch binds cleanly and
        // no stale file is left for a client to connect to and wait on.
        controlServer?.stop()
        controlServer = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// The control socket: `PROTOCOL.md` §1's transport, wired to the behaviour that
    /// already exists in-process.
    ///
    /// The verbs that have an in-process implementation are mapped here; `emote` and
    /// `face` do not exist yet and answer `unsupported`, which is what that error code
    /// is for. A pet with no control socket is not a broken pet, so a failure to bind
    /// is logged and survived rather than fatal.
    private func installControlServer() {
        let server = ControlServer()
        server.petNames = { [weak self] in
            (self?.cohort?.collection ?? []).filter(\.onDesk).map(\.name)
        }
        server.handler = { [weak self] intent in
            self?.perform(intent) ?? .refused(intent.id, .unsupported)
        }
        do {
            try server.start()
        } catch {
            Log.info("control: not listening — \(error)")
        }
        controlServer = server
    }

    /// One intent, mapped onto behaviour that already exists.
    private func perform(_ intent: Intent) -> IntentAck {
        guard let cohort else { return .refused(intent.id, .unknownPet) }
        switch intent.verb {
        case .say:
            guard let text = intent.args["text"] as? String else {
                return .refused(intent.id, .badArgs)
            }
            let style = (intent.args["style"] as? String).flatMap(BubbleStyle.init(rawValue:)) ?? .plain
            // Through the same per-producer budget the notification bridge uses: the
            // protocol names the producer, so a chatty client is limited like any
            // other.
            let producer = (intent.args["producer"] as? String) ?? "socket"
            _ = cohort.say(text, style: style, from: producer)
            return .started(intent.id)

        case .hide, .show:
            cohort.setHidden(intent.verb == .hide)
            return .started(intent.id)

        case .spawn:
            guard cohort.spawn() != nil else { return .refused(intent.id, .capacity) }
            return .started(intent.id)

        case .despawn:
            guard cohort.removePet(at: cohort.count - 1) else {
                return .refused(intent.id, .capacity)
            }
            return .started(intent.id)

        case .moveTo:
            guard let x = intent.args["x"] as? Double, let y = intent.args["y"] as? Double else {
                return .refused(intent.id, .badArgs)
            }
            cohort.spokespet?.motion.move(to: CGPoint(x: x, y: y), animated: true)
            return .started(intent.id)

        case .state:
            // The same line the ctrl-opt-D hotkey logs: one description, one place.
            describeState()
            return .started(intent.id)

        case .emote, .face, .bubbleShow, .bubbleAppend, .bubbleHide, .lookAt, .petOn:
            // Understood, and not implemented at this version — which is exactly what
            // `unsupported` means, and better than pretending to accept it.
            return .refused(intent.id, .unsupported)
        }
    }

    /// Pause everything while the screen is locked or the machine is asleep.
    ///
    /// Two sources, because macOS splits them: `NSWorkspace` knows about sleep, and
    /// the screen lock is a distributed notification. Both are permission-free —
    /// observing is not capturing, and neither needs Accessibility or Screen
    /// Recording. `Pookie --simulate-lock on` posts the same notification, which is
    /// how the wiring is exercised without locking a real screen.
    private func installPauseObservers() {
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

    private func installSayBridge() {
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

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Pookie")
            button.image?.isTemplate = true
            button.toolTip = "Pookie"
        }
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let pets = cohort?.count ?? 0

        let header = NSMenuItem(
            title: pets > 1 ? "Pookie (\(pets) cats)" : "Pookie",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let visibility = NSMenuItem(
            title: cohort?.someHidden == true ? "Show all pookies" : "Hide all pookies",
            action: #selector(toggleVisibility),
            keyEquivalent: "h"
        )
        visibility.target = self
        menu.addItem(visibility)

        let reset = NSMenuItem(title: "Bring Pookie Home", action: #selector(resetPosition), keyEquivalent: "r")
        reset.target = self
        menu.addItem(reset)

        // Settings. Both of these are about where and how big she is, which is
        // the pair of things a desktop pet owner actually wants to control.
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for scale in CatScale.allCases {
            let item = NSMenuItem(title: scale.label, action: #selector(selectScale(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = scale.rawValue
            item.state = AppConfig.shared.petScale == scale ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let teleport = NSMenuItem(
            title: "Teleport between displays",
            action: #selector(toggleTeleport),
            keyEquivalent: ""
        )
        teleport.target = self
        teleport.state = AppConfig.shared.teleportEnabled ? .on : .off
        teleport.isEnabled = NSScreen.screens.count > 1
        teleport.toolTip = teleport.isEnabled
            ? "Blink to another display every so often"
            : "Needs a second display"
        menu.addItem(teleport)

        let cadenceItem = NSMenuItem(title: "Teleport every", action: nil, keyEquivalent: "")
        cadenceItem.indentationLevel = 1
        let cadenceMenu = NSMenu()
        for cadence in TeleportCadence.allCases {
            let item = NSMenuItem(title: cadence.label, action: #selector(selectCadence(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = cadence.rawValue
            item.state = AppConfig.shared.teleportCadence == cadence ? .on : .off
            cadenceMenu.addItem(item)
        }
        cadenceItem.submenu = cadenceMenu
        menu.addItem(cadenceItem)

        menu.addItem(.separator())

        let addItem = NSMenuItem(
            title: pets >= PetCohort.maximumPets
                ? "Add a pookie (\(PetCohort.maximumPets) is the limit)"
                : "Add a pookie",
            action: nil,
            keyEquivalent: ""
        )
        let addMenu = NSMenu()
        for species in PetSpecies.allCases {
            let item = NSMenuItem(title: species.name, action: #selector(addPookie(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = species.rawValue
            // One of each animal: a kind that is already on the desk is offered
            // but disabled, with the reason in the tooltip. A missing item looks
            // like a bug; a greyed one looks like a rule.
            // The collection, not the desk: an animal you already own but have
            // switched off is not something "Add" can add, and an item that does
            // nothing when clicked reads as a bug.
            let owned = cohort?.collection.contains { $0.species == species } ?? false
            item.isEnabled = !owned && (cohort?.count ?? 0) < PetCohort.maximumPets
            item.toolTip = owned
                ? "\(species.name) is already in your collection — switch it on in Pookies"
                : nil
            addMenu.addItem(item)
        }
        addItem.submenu = addMenu
        menu.addItem(addItem)


        // The desk at a glance, and the way into the real settings window. The
        // per-pookie submenus used to live here; a menu with seventeen animals and
        // four submenus each is a menu pretending to be a settings screen, so the
        // configuration moved to Settings and this stayed a summary.
        let pookiesItem = NSMenuItem(title: "Pookies", action: nil, keyEquivalent: "")
        let pookiesMenu = NSMenu()
        let collection = cohort?.collection ?? []
        let onDesk = cohort?.count ?? 0
        let summary = NSMenuItem(
            title: "\(onDesk) on the desk · \(collection.count) in the collection",
            action: nil,
            keyEquivalent: ""
        )
        summary.isEnabled = false
        pookiesMenu.addItem(summary)
        for entry in collection {
            let marker = entry.onDesk ? "●" : "○"
            let boss = AppConfig.shared.roster.firstIndex(of: entry) == AppConfig.shared.boss ? "  (boss)" : ""
            let item = NSMenuItem(
                title: "\(marker) \(entry.name) · \(entry.species.name) · \(entry.coat.name)\(boss)",
                action: #selector(toggleSpeciesOnDesk(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = entry.species.rawValue
            item.state = entry.onDesk ? .on : .off
            item.toolTip = entry.onDesk ? "On the desk — click to take it off" : "In the collection — click to put it on the desk"
            pookiesMenu.addItem(item)
        }
        pookiesMenu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        pookiesMenu.addItem(settingsItem)
        pookiesItem.submenu = pookiesMenu
        menu.addItem(pookiesItem)

        menu.addItem(.separator())

        let clickThroughHeader = NSMenuItem(title: "Mouse", action: nil, keyEquivalent: "")
        clickThroughHeader.isEnabled = false
        menu.addItem(clickThroughHeader)

        for mode in ClickThroughMode.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(selectClickThrough(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = AppConfig.shared.clickThroughMode == mode ? .on : .off
            item.indentationLevel = 1
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let wander = NSMenuItem(title: "Wander around", action: #selector(toggleWander), keyEquivalent: "")
        wander.target = self
        wander.state = AppConfig.shared.wanderEnabled ? .on : .off
        menu.addItem(wander)

        let follow = NSMenuItem(title: "Watch the cursor", action: #selector(toggleFollowCursor), keyEquivalent: "")
        follow.target = self
        follow.state = AppConfig.shared.followCursor ? .on : .off
        menu.addItem(follow)

        let perch = NSMenuItem(title: "Sit on windows", action: #selector(togglePerch), keyEquivalent: "")
        perch.target = self
        perch.state = AppConfig.shared.perchEnabled ? .on : .off
        menu.addItem(perch)

        let jump = NSMenuItem(title: "Jump onto windows", action: #selector(toggleJump), keyEquivalent: "")
        jump.target = self
        jump.state = AppConfig.shared.jumpEnabled ? .on : .off
        jump.indentationLevel = 1
        menu.addItem(jump)

        let privacy = NSMenuItem(
            title: "Hide from screen sharing",
            action: #selector(toggleScreenSharePrivacy),
            keyEquivalent: ""
        )
        privacy.target = self
        privacy.state = AppConfig.shared.hideFromScreenShare ? .on : .off
        menu.addItem(privacy)

        let raised = NSMenuItem(
            title: "Float above full-screen apps",
            action: #selector(toggleRaised),
            keyEquivalent: ""
        )
        raised.target = self
        raised.state = cohort?.isRaisedAboveEverything == true ? .on : .off
        menu.addItem(raised)

        menu.addItem(.separator())

        let speechHeader = NSMenuItem(title: "Speech", action: nil, keyEquivalent: "")
        speechHeader.isEnabled = false
        menu.addItem(speechHeader)

        let chatty = NSMenuItem(
            title: "React to being petted",
            action: #selector(toggleChatty),
            keyEquivalent: ""
        )
        chatty.target = self
        chatty.state = AppConfig.shared.chatty ? .on : .off
        chatty.indentationLevel = 1
        menu.addItem(chatty)

        let hello = NSMenuItem(title: "Say hello", action: #selector(sayHello), keyEquivalent: "")
        hello.target = self
        hello.indentationLevel = 1
        menu.addItem(hello)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Pookie", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    // MARK: - Hot keys
    //
    // Carbon hot keys need no Accessibility permission, so these work on a
    // fresh machine with zero prompts.

    private func installHotKeys() {
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
                modifiers: GlobalHotKey.controlOption,
                action: { [weak self] in _ = self?.perform(selector) }
            ) else { continue }
            hotKeys.append(hotKey)
            Log.info("bound ctrl-opt-\(key) -> \(name)")
        }
    }

    // MARK: - Actions

    @objc private func toggleVisibility() {
        cohort?.toggleHidden()
        rebuildMenu()
    }

    @objc private func cycleClickThrough() {
        cohort?.cycleClickThrough()
        rebuildMenu()
    }

    @objc private func resetPosition() {
        cohort?.bringAllHome()
    }

    @objc private func selectScale(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let scale = CatScale(rawValue: raw) else { return }
        AppConfig.shared.petScale = scale
        cohort?.applyPetScale()
        rebuildMenu()
    }

    @objc private func toggleTeleport() {
        AppConfig.shared.teleportEnabled.toggle()
        cohort?.setTeleporting(AppConfig.shared.teleportEnabled)
        rebuildMenu()
    }

    /// Everything one pet's right-click menu needs to know.
    ///
    /// A value rather than the live controller, so the menu can be built — and
    /// checked — without a colony or a window server. The menu is a claim about
    /// what the user can do to *this* pet, and that claim is worth a test.
    struct PetMenuState {
        var index: Int
        var name: String
        var species: PetSpecies
        var coat: CatSkin
        var count: Int
        var isHidden: Bool
        var isBoss: Bool
        var someHidden: Bool
    }

    /// The items a pet offers when you right-click it.
    static func petMenu(for state: PetMenuState, target: AnyObject?) -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(
            title: "\(state.name) · \(state.species.name) · \(state.coat.name)\(state.isBoss ? "  (pookie boss)" : "")",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        let position = NSMenuItem(
            title: "\(state.index + 1) of \(state.count) on the desk",
            action: nil,
            keyEquivalent: ""
        )
        position.isEnabled = false
        menu.addItem(position)

        menu.addItem(.separator())
        let home = NSMenuItem(
            title: "Bring this one home",
            action: #selector(AppDelegate.bringHomePet(_:)),
            keyEquivalent: ""
        )
        home.target = target
        home.tag = state.index
        menu.addItem(home)

        let rename = NSMenuItem(
            title: "Rename…",
            action: #selector(AppDelegate.renamePookie(_:)),
            keyEquivalent: ""
        )
        rename.target = target
        rename.tag = state.index
        menu.addItem(rename)

        let boss = NSMenuItem(
            title: "Make Pookie Boss",
            action: #selector(AppDelegate.makePookieBoss(_:)),
            keyEquivalent: ""
        )
        boss.target = target
        boss.tag = state.index
        boss.state = state.isBoss ? .on : .off
        boss.toolTip = "The pookie boss speaks when a producer sends her a line"
        menu.addItem(boss)

        menu.addItem(.separator())
        // The point of the whole menu: this pet, not the newest one.
        let hide = NSMenuItem(
            title: state.isHidden ? "Show this pookie" : "Hide this pookie",
            action: #selector(AppDelegate.togglePetHidden(_:)),
            keyEquivalent: ""
        )
        hide.target = target
        hide.tag = state.index
        menu.addItem(hide)

        if state.someHidden {
            let showAll = NSMenuItem(
                title: "Show all pookies",
                action: #selector(AppDelegate.toggleVisibility),
                keyEquivalent: ""
            )
            showAll.target = target
            menu.addItem(showAll)
        }

        let remove = NSMenuItem(
            title: "Remove this pookie",
            action: #selector(AppDelegate.removePookie(_:)),
            keyEquivalent: ""
        )
        remove.target = target
        remove.tag = state.index
        remove.isEnabled = state.count > 1
        remove.toolTip = state.count > 1
            ? "Takes this one off the desk and out of the roster"
            : "The last pookie stays: quit Pookie instead"
        menu.addItem(remove)

        return menu
    }

    /// The same menu, for a live pet.
    func petMenu(for pet: PetWindowController) -> NSMenu? {
        guard let index = cohort?.pets.firstIndex(where: { $0 === pet }) else { return nil }
        return Self.petMenu(
            for: PetMenuState(
                index: index,
                name: pet.pookie.name,
                species: pet.pookie.species,
                coat: pet.pookie.coat,
                count: cohort?.pets.count ?? 1,
                isHidden: pet.isHiddenByUser,
                isBoss: index == AppConfig.shared.boss,
                someHidden: cohort?.someHidden ?? false
            ),
            target: self
        )
    }

    @objc private func togglePetHidden(_ sender: NSMenuItem) {
        guard let pet = cohort?.pets[safe: sender.tag] else { return }
        cohort?.setHidden(!pet.isHiddenByUser, at: sender.tag)
        rebuildMenu()
    }

    @objc private func removePookie(_ sender: NSMenuItem) {
        cohort?.removePet(at: sender.tag)
        rebuildMenu()
    }

    @objc private func bringHomePet(_ sender: NSMenuItem) {
        guard let pet = cohort?.pets[safe: sender.tag] else { return }
        pet.resetPosition()
        // Bringing one home also shows it: asking for a pet you cannot see would
        // otherwise look like nothing happened.
        if pet.isHiddenByUser {
            cohort?.setHidden(false, at: sender.tag)
            rebuildMenu()
        }
    }

    /// Add or remove the login item, reporting rather than assuming. Shared by the
    /// settings checkbox and `--launch-at-login`, so both take the same path.
    @discardableResult
    static func setLaunchAtLogin(_ wanted: Bool) -> Bool {
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

    /// Open (or raise) the settings window.
    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(cohort: cohort ?? PetCohort()) { [weak self] in
                self?.rebuildMenu()
            }
        }
        settingsWindow?.present()
    }

    /// Put one animal on the desk, or take it off — from the Pookies summary.
    @objc private func toggleSpeciesOnDesk(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let species = PetSpecies(rawValue: raw) else { return }
        let entry = cohort?.collection.first { $0.species == species }
        let wanted = !(entry?.onDesk ?? false)
        if cohort?.setOnDesk(wanted, species: species) != true {
            NSSound.beep()
        }
        rebuildMenu()
    }

    @objc private func addPookie(_ sender: NSMenuItem) {
        let raw = sender.representedObject as? String ?? ""
        cohort?.spawn(species: PetSpecies(rawValue: raw))
        rebuildMenu()
    }

    @objc private func selectSpecies(_ sender: NSMenuItem) {
        guard let pet = cohort?.pets[safe: sender.tag],
              let raw = sender.representedObject as? String,
              let species = PetSpecies(rawValue: raw) else { return }
        cohort?.setPookie(PookieConfig(species: species, coat: pet.pookie.coat), at: sender.tag)
        rebuildMenu()
    }

    @objc private func selectCoat(_ sender: NSMenuItem) {
        guard let pet = cohort?.pets[safe: sender.tag],
              let raw = sender.representedObject as? String,
              let coat = CatSkin(rawValue: raw) else { return }
        cohort?.setPookie(PookieConfig(species: pet.pookie.species, coat: coat), at: sender.tag)
        rebuildMenu()
    }

    @objc private func selectPattern(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let pattern = PookiePattern(rawValue: raw) else { return }
        cohort?.setPattern(pattern, at: sender.tag)
        rebuildMenu()
    }

    @objc private func renamePookie(_ sender: NSMenuItem) {
        guard let pet = cohort?.pets[safe: sender.tag] else { return }
        let alert = NSAlert()
        alert.messageText = "Name this pookie"
        alert.informativeText = "At the moment it is called \(pet.pookie.name)."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = pet.pookie.name
        field.placeholderString = pet.pookie.species.defaultName
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        // The app is an accessory, so it has to be brought forward for a modal
        // alert to be typeable.
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            cohort?.renamePookie(at: sender.tag, to: field.stringValue)
        }
        rebuildMenu()
    }

    @objc private func makePookieBoss(_ sender: NSMenuItem) {
        cohort?.makeDefault(index: sender.tag)
        rebuildMenu()
    }

    @objc private func selectCadence(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let cadence = TeleportCadence(rawValue: raw) else { return }
        AppConfig.shared.teleportCadence = cadence
        cohort?.applyTeleportCadence()
        rebuildMenu()
    }



    @objc private func selectClickThrough(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ClickThroughMode(rawValue: raw) else { return }
        AppConfig.shared.clickThroughMode = mode
        cohort?.applyClickThroughMode()
        rebuildMenu()
    }

    @objc private func toggleWander() {
        AppConfig.shared.wanderEnabled.toggle()
        for pet in cohort?.pets ?? [] {
            pet.motion.wanderEnabled = AppConfig.shared.wanderEnabled
        }
        rebuildMenu()
    }

    @objc private func toggleFollowCursor() {
        AppConfig.shared.followCursor.toggle()
        for pet in cohort?.pets ?? [] {
            pet.motion.followCursor = AppConfig.shared.followCursor
        }
        rebuildMenu()
    }

    @objc private func togglePerch() {
        AppConfig.shared.perchEnabled.toggle()
        cohort?.setPerching(AppConfig.shared.perchEnabled)
        rebuildMenu()
    }

    @objc private func toggleJump() {
        AppConfig.shared.jumpEnabled.toggle()
        cohort?.setJumping(AppConfig.shared.jumpEnabled)
        rebuildMenu()
    }

    @objc private func toggleChatty() {
        AppConfig.shared.chatty.toggle()
        cohort?.setChatty(AppConfig.shared.chatty)
        rebuildMenu()
    }

    @objc private func sayHello() {
        cohort?.say(PetChatter.tapped(), style: .plain)
    }

    @objc private func toggleScreenSharePrivacy() {
        AppConfig.shared.hideFromScreenShare.toggle()
        cohort?.applyScreenSharePrivacy()
        rebuildMenu()
    }

    @objc private func toggleRaised() {
        guard let cohort else { return }
        cohort.isRaisedAboveEverything.toggle()
        cohort.applyRaisedAboveEverything()
        rebuildMenu()
    }

    @objc private func describeState() {
        guard let cohort else { return }
        let pets = cohort.pets.map { pet -> String in
            let motion = pet.motion
            let perch = motion.supportPlatform().map { "\($0.ownerName)#\($0.windowNumber)" } ?? "floor"
            return "\(pet.pookie.species.rawValue)/\(pet.pookie.coat.rawValue)@\(NSStringFromPoint(motion.origin)) "
                + "\(motion.pose.mood.rawValue)/\(motion.shape.rawValue) perch=\(perch)"
                + (motion.isPlaying ? " playing" : "")
        }
        Log.info("""
        state: \(pets.count) pet\(pets.count == 1 ? "" : "s") \
        hidden=\(cohort.isHiddenByUser) \
        mouse=\(AppConfig.shared.clickThroughMode.rawValue) \
        maskRowZeroIsBottom=\(MaskRaster.rowZeroIsBottom)
          \(pets.joined(separator: "\n  "))
        """)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Keep the menu honest while it is open: displays get plugged and unplugged, the
/// population changes, and the settings can also arrive from the command line.
extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleTeleport) {
            menuItem.state = AppConfig.shared.teleportEnabled ? .on : .off
            return NSScreen.screens.count > 1
        }
        if menuItem.action == #selector(selectScale(_:)), let raw = menuItem.representedObject as? String {
            menuItem.state = AppConfig.shared.petScale.rawValue == raw ? .on : .off
        }
        if menuItem.action == #selector(addPookie(_:)), let raw = menuItem.representedObject as? String {
            guard let species = PetSpecies(rawValue: raw) else { return false }
            return cohort?.canAdd(species: species) ?? false
        }
        if menuItem.action == #selector(selectSpecies(_:)),
           let pet = cohort?.pets[safe: menuItem.tag],
           let raw = menuItem.representedObject as? String {
            menuItem.state = pet.pookie.species.rawValue == raw ? .on : .off
        }
        if menuItem.action == #selector(selectPattern(_:)),
           let pet = cohort?.pets[safe: menuItem.tag],
           let raw = menuItem.representedObject as? String {
            menuItem.state = pet.pookie.pattern.rawValue == raw ? .on : .off
        }
        if menuItem.action == #selector(selectCoat(_:)),
           let pet = cohort?.pets[safe: menuItem.tag],
           let raw = menuItem.representedObject as? String {
            menuItem.state = pet.pookie.coat.rawValue == raw ? .on : .off
        }
        if menuItem.action == #selector(makePookieBoss(_:)) {
            menuItem.state = menuItem.tag == AppConfig.shared.boss ? .on : .off
        }
        if menuItem.action == #selector(selectCadence(_:)), let raw = menuItem.representedObject as? String {
            menuItem.state = AppConfig.shared.teleportCadence.rawValue == raw ? .on : .off
        }
        if menuItem.action == #selector(removePookie(_:)) {
            return (cohort?.count ?? 0) > 1
        }
        return true
    }
}
