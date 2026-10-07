import AppKit

/// Pookie runs as an `.accessory` app: no Dock icon, no menu bar of its own.
/// The status item is the only UI, because a pet you cannot easily quit is a
/// pet you will resent.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The `pookie say "hi"` bridge. A distributed notification is the
    /// permission-free way for another process to reach a running pet; it is a
    /// stand-in for the M3 loopback socket protocol, and the shape of the call
    /// (`controller.say`) is the same either way.
    static let sayNotification = Notification.Name("com.pookie.pet.say")

    private var controller: PetWindowController?
    private var statusItem: NSStatusItem?
    private var hotKeys: [GlobalHotKey] = []
    private var sayObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.verbose = AppConfig.shared.verboseLogging
        controller = PetWindowController()
        installStatusItem()
        installHotKeys()
        installSayBridge()
    }

    deinit {
        if let sayObserver {
            DistributedNotificationCenter.default().removeObserver(sayObserver)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func installSayBridge() {
        sayObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.sayNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let text = note.userInfo?["text"] as? String else { return }
            let style = (note.userInfo?["style"] as? String).flatMap(BubbleStyle.init(rawValue:)) ?? .plain
            self?.controller?.say(text, style: style)
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

        let header = NSMenuItem(title: "Pookie", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let visibility = NSMenuItem(
            title: controller?.isHiddenByUser == true ? "Show Pookie" : "Hide Pookie",
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
            ? "Blink to another display every minute or so"
            : "Needs a second display"
        menu.addItem(teleport)

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
        raised.state = controller?.isRaisedAboveEverything == true ? .on : .off
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
        controller?.toggleHidden()
        rebuildMenu()
    }

    @objc private func cycleClickThrough() {
        controller?.toggleClickThrough()
        rebuildMenu()
    }

    @objc private func resetPosition() {
        controller?.resetPosition()
    }

    @objc private func selectScale(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let scale = CatScale(rawValue: raw) else { return }
        AppConfig.shared.petScale = scale
        controller?.applyPetScale()
        rebuildMenu()
    }

    @objc private func toggleTeleport() {
        AppConfig.shared.teleportEnabled.toggle()
        controller?.motion.teleportEnabled = AppConfig.shared.teleportEnabled
        rebuildMenu()
    }

    @objc private func selectClickThrough(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ClickThroughMode(rawValue: raw) else { return }
        AppConfig.shared.clickThroughMode = mode
        controller?.applyClickThroughMode()
        rebuildMenu()
    }

    @objc private func toggleWander() {
        AppConfig.shared.wanderEnabled.toggle()
        controller?.motion.wanderEnabled = AppConfig.shared.wanderEnabled
        rebuildMenu()
    }

    @objc private func toggleFollowCursor() {
        AppConfig.shared.followCursor.toggle()
        controller?.motion.followCursor = AppConfig.shared.followCursor
        rebuildMenu()
    }

    @objc private func togglePerch() {
        AppConfig.shared.perchEnabled.toggle()
        controller?.setPerching(AppConfig.shared.perchEnabled)
        rebuildMenu()
    }

    @objc private func toggleJump() {
        AppConfig.shared.jumpEnabled.toggle()
        controller?.setJumping(AppConfig.shared.jumpEnabled)
        rebuildMenu()
    }

    @objc private func toggleChatty() {
        AppConfig.shared.chatty.toggle()
        controller?.setChatty(AppConfig.shared.chatty)
        rebuildMenu()
    }

    @objc private func sayHello() {
        controller?.say(PetChatter.tapped(), style: .plain)
    }

    @objc private func toggleScreenSharePrivacy() {
        AppConfig.shared.hideFromScreenShare.toggle()
        controller?.applyScreenSharePrivacy()
        rebuildMenu()
    }

    @objc private func toggleRaised() {
        guard let controller else { return }
        controller.setRaisedAboveEverything(!controller.isRaisedAboveEverything)
        rebuildMenu()
    }

    @objc private func describeState() {
        guard let controller else { return }
        let motion = controller.motion
        Log.info("""
        state: origin=\(NSStringFromPoint(motion.origin)) \
        size=\(Int(motion.size.width))x\(Int(motion.size.height)) \
        shape=\(motion.shape.rawValue) \
        mood=\(motion.pose.mood.rawValue) \
        velocity=(\(Int(motion.velocity.dx)), \(Int(motion.velocity.dy))) \
        hidden=\(controller.isHiddenByUser) \
        mouse=\(AppConfig.shared.clickThroughMode.rawValue) \
        maskRowZeroIsBottom=\(MaskRaster.rowZeroIsBottom)
        """)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Keep the menu honest while it is open: displays get plugged and unplugged,
/// and the settings can also arrive from the command line.
extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleTeleport) {
            menuItem.state = AppConfig.shared.teleportEnabled ? .on : .off
            return NSScreen.screens.count > 1
        }
        if menuItem.action == #selector(selectScale(_:)), let raw = menuItem.representedObject as? String {
            menuItem.state = AppConfig.shared.petScale.rawValue == raw ? .on : .off
        }
        return true
    }
}
