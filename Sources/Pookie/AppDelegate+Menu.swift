import AppKit

extension AppDelegate {
    // MARK: - Status item

    func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: AppIdentity.current.displayName)
            button.image?.isTemplate = true
            button.title = AppIdentity.current.statusItemTitle
            button.imagePosition = .imageLeading
            button.toolTip = AppIdentity.current.displayName
        }
        statusItem = item
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()
        let pets = cohort?.count ?? 0

        let header = NSMenuItem(
            title: pets > 1 ? "\(AppIdentity.current.displayName) (\(pets) cats)" : AppIdentity.current.displayName,
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

        addReleaseItems(to: menu)

        let quit = NSMenuItem(title: "Quit \(AppIdentity.current.displayName)", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
    }

}

/// Keep the menu honest while it is open: displays get plugged and unplugged, the
/// population changes, and the settings can also arrive from the command line.
extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates) {
            return updateController?.canCheckForUpdates ?? false
        }
        if menuItem.action == #selector(toggleAutomaticUpdates) {
            menuItem.state = updateController?.automaticallyChecksForUpdates == true ? .on : .off
            return updateController?.isEnabled ?? false
        }
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
