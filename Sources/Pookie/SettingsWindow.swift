import AppKit
import ServiceManagement

/// The settings window.
///
/// The menu bar keeps the things you reach for while the pookies are running —
/// hide, add one, quit. Everything you *configure* lives here, because a menu of
/// seventeen animals with four submenus each is not a settings screen: it is a
/// menu pretending to be one. Three tabs, the collection as a list you can edit,
/// and the switches grouped by what they affect.
final class SettingsWindowController: NSWindowController {
    private weak var cohort: PetCohort?
    /// Called after anything changes, so the menu and the pets catch up.
    private let onChange: () -> Void

    /// The tab you were last on. Landing back where you left off is the whole
    /// reason a settings window remembers anything.
    private var selectedTab: Int {
        get { UserDefaults.standard.integer(forKey: "settingsTab") }
        set { UserDefaults.standard.set(newValue, forKey: "settingsTab") }
    }

    private var tabs: NSTabView?
    private var generalTab: NSView!
    private var behaviourTab: NSView!
    private var pookiesTab: NSView!
    private var pookieRows: NSStackView!

    init(cohort: PetCohort, onChange: @escaping () -> Void) {
        self.cohort = cohort
        self.onChange = onChange

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pookie Settings"
        window.isReleasedWhenClosed = false
        // Above the pets, and it does not become the app's main window: the
        // pookies keep running while you are in here.
        window.level = .floating
        // The pookies ride every Space, so their settings have to be reachable
        // from wherever you are — including over a full-screen app, which is
        // exactly where you would be looking for them.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()

        super.init(window: window)
        buildTabs()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Bring the window up, refreshing it from the current settings.
    func present() {
        Log.info("settings window up")
        if let tabs, let index = tabs.tabViewItems.firstIndex(of: tabs.selectedTabViewItem ?? NSTabViewItem()) {
            selectedTab = index
        }
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildTabs() {
        let tabs = NSTabView(frame: .zero)
        tabs.translatesAutoresizingMaskIntoConstraints = false

        generalTab = buildGeneral()
        behaviourTab = buildBehaviour()
        pookiesTab = buildPookies()

        for (title, view) in [
            ("General", generalTab),
            ("Behaviour", behaviourTab),
            ("Pookies", pookiesTab),
        ] {
            let item = NSTabViewItem(identifier: title)
            item.label = title
            item.view = view
            tabs.addTabViewItem(item)
        }

        self.tabs = tabs
        tabs.selectTabViewItem(at: min(max(selectedTab, 0), tabs.numberOfTabViewItems - 1))
        guard let content = window?.contentView else { return }
        content.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabs.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - Building

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 11)
        return label
    }

    private func section(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return stack
    }

    private func checkbox(_ title: String, _ action: Selector, tooltip: String? = nil) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.toolTip = tooltip
        return button
    }

    private func buildGeneral() -> NSView {
        let config = AppConfig.shared

        let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for scale in CatScale.allCases { sizePopup.addItem(withTitle: scale.name) }
        sizePopup.selectItem(at: CatScale.allCases.firstIndex(of: config.petScale) ?? 1)
        sizePopup.target = self
        sizePopup.action = #selector(sizeChanged(_:))

        let cadencePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for cadence in TeleportCadence.allCases { cadencePopup.addItem(withTitle: cadence.label) }
        cadencePopup.selectItem(at: TeleportCadence.allCases.firstIndex(of: config.teleportCadence) ?? 1)
        cadencePopup.target = self
        cadencePopup.action = #selector(cadenceChanged(_:))

        let login = checkbox(
            "Start Pookie when I log in",
            #selector(toggleLogin(_:)),
            tooltip: "Adds Pookie to your login items. Needs the app bundle, so it does nothing when running the debug binary"
        )
        login.state = config.launchAtLogin ? .on : .off

        let teleport = checkbox(
            "Blink between displays",
            #selector(toggleTeleport(_:)),
            tooltip: "Only does anything with more than one display attached"
        )
        teleport.state = config.teleportEnabled ? .on : .off

        let opacity = NSSlider(value: config.petOpacity, minValue: 0.35, maxValue: 1, target: self, action: #selector(opacityChanged(_:)))
        opacity.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let opacityRow = NSStackView(views: [NSTextField(labelWithString: "Opacity"), opacity])
        opacityRow.orientation = .horizontal
        opacityRow.spacing = 12

        let sizeRow = NSStackView(views: [NSTextField(labelWithString: "Size"), sizePopup])
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 12
        let cadenceRow = NSStackView(views: [NSTextField(labelWithString: "Teleport every"), cadencePopup])
        cadenceRow.orientation = .horizontal
        cadenceRow.spacing = 12

        let stack = section([
            heading("The desk"),
            sizeRow,
            opacityRow,
            login,
            teleport,
            cadenceRow,
            caption("A bigger pookie is a real size change: the window, the drawing and the behaviour geometry all scale together, so she still fits the ledge she jumps to."),
        ])
        return stack
    }

    private func buildBehaviour() -> NSView {
        let config = AppConfig.shared

        func row(_ title: String, _ action: Selector, _ on: Bool, _ tooltip: String) -> NSButton {
            let button = checkbox(title, action, tooltip: tooltip)
            button.state = on ? .on : .off
            return button
        }

        let stack = section([
            heading("What they do"),
            row("Wander around on their own", #selector(toggleWander(_:)), config.wanderEnabled,
                "Off means they stay where you put them — except for a scrap, which two neighbours will still have"),
            row("Watch the cursor", #selector(toggleCursor(_:)), config.followCursor,
                "Follow the pointer with their eyes, and drift back to the display you are working on"),
            row("Sit on top of windows", #selector(togglePerch(_:)), config.perchEnabled,
                "Land on the top edges of other apps' windows instead of falling past them"),
            row("Jump up onto them by themselves", #selector(toggleJump(_:)), config.jumpEnabled,
                "Off means they only perch when you drop them there"),
            row("Quiet mode", #selector(toggleQuiet(_:)), config.quietMode,
                "No unprompted lines: no greeting, no yelp, no achoo. A producer asking her to speak still works"),
            row("Chatty", #selector(toggleChatty(_:)), config.chatty,
                "React to being petted, thrown and perched on. Off means they only speak when a producer tells them to"),
            heading("Privacy"),
            row("Hide from screen sharing", #selector(togglePrivacy(_:)), config.hideFromScreenShare,
                "Keeps the pookies out of screen recordings and captures"),
            row("Float above full-screen apps", #selector(toggleRaised(_:)), false,
                "Some full-screen apps sit above a floating window; this raises them over everything"),
        ])
        return stack
    }

    private func buildPookies() -> NSView {
        let header = NSStackView(views: [
            heading("The collection"),
        ])
        header.orientation = .vertical
        header.alignment = .leading

        let explanation = caption(
            "Every pookie you have configured lives here. Tick one to put it on the desk — "
            + "the desk holds at most \(PetCohort.maximumPets) at a time, because that is the part that costs."
        )

        pookieRows = NSStackView()
        pookieRows.orientation = .vertical
        pookieRows.alignment = .leading
        pookieRows.spacing = 6

        let addPopup = NSPopUpButton(frame: .zero, pullsDown: true)
        addPopup.addItem(withTitle: "Add a pookie")
        for species in PetSpecies.allCases {
            addPopup.addItem(withTitle: species.name)
        }
        addPopup.target = self
        addPopup.action = #selector(addSpecies(_:))

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = pookieRows
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        let stack = NSStackView(views: [header, explanation, scroll, addPopup])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        pookieRows.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
        return stack
    }

    // MARK: - The collection list

    /// One row per configured pookie: on the desk, what it is called, what it is,
    /// what it is wearing.
    private func reloadPookieRows() {
        guard let cohort, let rows = pookieRows else { return }
        for view in rows.arrangedSubviews { rows.removeArrangedSubview(view); view.removeFromSuperview() }

        Log.info("settings: \(cohort.collection.count) in the collection, \(cohort.count) on the desk")
        for (index, entry) in cohort.collection.enumerated() {
            let onDesk = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleOnDesk(_:)))
            onDesk.state = entry.onDesk ? .on : .off
            onDesk.tag = index
            onDesk.toolTip = entry.onDesk ? "On the desk" : "In the collection, not on the desk"
            onDesk.widthAnchor.constraint(equalToConstant: 20).isActive = true

            let name = NSTextField(string: entry.name)
            name.tag = index
            name.target = self
            name.action = #selector(nameChanged(_:))
            name.widthAnchor.constraint(equalToConstant: 110).isActive = true

            let species = NSPopUpButton(frame: .zero, pullsDown: false)
            for candidate in PetSpecies.allCases { species.addItem(withTitle: candidate.name) }
            species.selectItem(at: PetSpecies.allCases.firstIndex(of: entry.species) ?? 0)
            species.tag = index
            species.target = self
            species.action = #selector(speciesChanged(_:))

            let coat = NSPopUpButton(frame: .zero, pullsDown: false)
            for candidate in CatSkin.allCases { coat.addItem(withTitle: candidate.name) }
            coat.selectItem(at: CatSkin.allCases.firstIndex(of: entry.coat) ?? 0)
            coat.tag = index
            coat.target = self
            coat.action = #selector(coatChanged(_:))

            let marking = NSPopUpButton(frame: .zero, pullsDown: false)
            for candidate in PookiePattern.allCases { marking.addItem(withTitle: candidate.name) }
            marking.selectItem(at: PookiePattern.allCases.firstIndex(of: entry.pattern) ?? 0)
            marking.tag = index
            marking.target = self
            marking.action = #selector(patternChanged(_:))

            let remove = NSButton(title: "Remove", target: self, action: #selector(removePookie(_:)))
            remove.tag = index
            remove.bezelStyle = .rounded

            let row = NSStackView(views: [onDesk, name, species, coat, marking, remove])
            row.orientation = .horizontal
            row.spacing = 8
            rows.addArrangedSubview(row)
        }
    }

    private func reload() {
        guard let config = AppConfig.shared as AppConfig? else { return }
        _ = config
        reloadPookieRows()
    }

    // MARK: - Actions

    private func changed() {
        onChange()
        reloadPookieRows()
    }

    @objc private func sizeChanged(_ sender: NSPopUpButton) {
        guard let scale = CatScale.allCases[safe: sender.indexOfSelectedItem] else { return }
        AppConfig.shared.petScale = scale
        cohort?.applyPetScale()
        changed()
    }

    @objc private func cadenceChanged(_ sender: NSPopUpButton) {
        guard let cadence = TeleportCadence.allCases[safe: sender.indexOfSelectedItem] else { return }
        AppConfig.shared.teleportCadence = cadence
        cohort?.applyTeleportCadence()
        changed()
    }

    @objc private func toggleTeleport(_ sender: NSButton) {
        AppConfig.shared.teleportEnabled = sender.state == .on
        cohort?.setTeleporting(AppConfig.shared.teleportEnabled)
        changed()
    }

    @objc private func toggleWander(_ sender: NSButton) {
        AppConfig.shared.wanderEnabled = sender.state == .on
        for pet in cohort?.pets ?? [] { pet.motion.wanderEnabled = AppConfig.shared.wanderEnabled }
        changed()
    }

    @objc private func toggleCursor(_ sender: NSButton) {
        AppConfig.shared.followCursor = sender.state == .on
        for pet in cohort?.pets ?? [] { pet.motion.followCursor = AppConfig.shared.followCursor }
        changed()
    }

    @objc private func togglePerch(_ sender: NSButton) {
        AppConfig.shared.perchEnabled = sender.state == .on
        for pet in cohort?.pets ?? [] { pet.motion.perchEnabled = AppConfig.shared.perchEnabled }
        changed()
    }

    @objc private func toggleJump(_ sender: NSButton) {
        AppConfig.shared.jumpEnabled = sender.state == .on
        for pet in cohort?.pets ?? [] { pet.motion.jumpEnabled = AppConfig.shared.jumpEnabled }
        changed()
    }

    /// Launch at login goes through `SMAppService`, which is the supported API
    /// and needs no permission prompt — but it does need a real app bundle, so
    /// the debug binary gets a beep and an explanation rather than a silent lie.
    @objc private func toggleLogin(_ sender: NSButton) {
        let wanted = sender.state == .on
        if !AppDelegate.setLaunchAtLogin(wanted) {
            sender.state = wanted ? .off : .on
            let alert = NSAlert()
            alert.messageText = wanted ? "Could not add Pookie to your login items" : "Could not remove it"
            alert.informativeText = "This works from the app bundle — `make bundle`, then open build/Pookie.app."
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        changed()
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        AppConfig.shared.petOpacity = sender.doubleValue
        cohort?.applyOpacity()
        changed()
    }

    @objc private func toggleQuiet(_ sender: NSButton) {
        AppConfig.shared.quietMode = sender.state == .on
        changed()
    }

    @objc private func toggleChatty(_ sender: NSButton) {
        AppConfig.shared.chatty = sender.state == .on
        cohort?.applyChattiness()
        changed()
    }

    @objc private func togglePrivacy(_ sender: NSButton) {
        AppConfig.shared.hideFromScreenShare = sender.state == .on
        cohort?.applyPrivacy()
        changed()
    }

    @objc private func toggleRaised(_ sender: NSButton) {
        cohort?.isRaisedAboveEverything = sender.state == .on
        cohort?.applyRaisedAboveEverything()
        changed()
    }

    @objc private func toggleOnDesk(_ sender: NSButton) {
        guard let entry = cohort?.collection[safe: sender.tag] else { return }
        let wanted = sender.state == .on
        if !(cohort?.setOnDesk(wanted, species: entry.species) ?? false) {
            // Refused: the desk is full, or it is the last one. Put the tick back.
            sender.state = wanted ? .off : .on
        }
        changed()
    }

    @objc private func nameChanged(_ sender: NSTextField) {
        guard let entry = cohort?.collection[safe: sender.tag] else { return }
        cohort?.rename(species: entry.species, to: sender.stringValue)
        changed()
    }

    @objc private func speciesChanged(_ sender: NSPopUpButton) {
        guard let entry = cohort?.collection[safe: sender.tag],
              let species = PetSpecies.allCases[safe: sender.indexOfSelectedItem] else { return }
        cohort?.changeSpecies(of: entry.species, to: species)
        changed()
    }

    @objc private func coatChanged(_ sender: NSPopUpButton) {
        guard let entry = cohort?.collection[safe: sender.tag],
              let coat = CatSkin.allCases[safe: sender.indexOfSelectedItem] else { return }
        cohort?.setCoat(coat, species: entry.species)
        changed()
    }

    @objc private func patternChanged(_ sender: NSPopUpButton) {
        guard let entry = cohort?.collection[safe: sender.tag],
              let pattern = PookiePattern.allCases[safe: sender.indexOfSelectedItem] else { return }
        cohort?.setPattern(pattern, species: entry.species)
        changed()
    }

    @objc private func removePookie(_ sender: NSButton) {
        guard let entry = cohort?.collection[safe: sender.tag] else { return }
        cohort?.removeFromCollection(species: entry.species)
        changed()
    }

    @objc private func addSpecies(_ sender: NSPopUpButton) {
        // The first item is the title, so the selection index is off by one.
        guard sender.indexOfSelectedItem > 0,
              let species = PetSpecies.allCases[safe: sender.indexOfSelectedItem - 1] else { return }
        cohort?.addToCollection(species: species)
        sender.selectItem(at: 0)
        changed()
    }
}
