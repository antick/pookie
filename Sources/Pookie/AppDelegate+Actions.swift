import AppKit

extension AppDelegate {
    // MARK: - Actions

    @objc func toggleVisibility() {
        cohort?.toggleHidden()
        rebuildMenu()
    }

    @objc func cycleClickThrough() {
        cohort?.cycleClickThrough()
        rebuildMenu()
    }

    @objc func resetPosition() {
        cohort?.bringAllHome()
    }

    @objc func selectScale(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let scale = CatScale(rawValue: raw) else { return }
        AppConfig.shared.petScale = scale
        cohort?.applyPetScale()
        rebuildMenu()
    }

    @objc func toggleTeleport() {
        AppConfig.shared.teleportEnabled.toggle()
        cohort?.setTeleporting(AppConfig.shared.teleportEnabled)
        rebuildMenu()
    }

    /// Open (or raise) the settings window.
    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(cohort: cohort ?? PetCohort()) { [weak self] in
                self?.rebuildMenu()
            }
        }
        settingsWindow?.present()
    }

    /// Put one animal on the desk, or take it off — from the Pookies summary.
    @objc func toggleSpeciesOnDesk(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let species = PetSpecies(rawValue: raw) else { return }
        let entry = cohort?.collection.first { $0.species == species }
        let wanted = !(entry?.onDesk ?? false)
        if cohort?.setOnDesk(wanted, species: species) != true {
            NSSound.beep()
        }
        rebuildMenu()
    }

    @objc func addPookie(_ sender: NSMenuItem) {
        let raw = sender.representedObject as? String ?? ""
        cohort?.spawn(species: PetSpecies(rawValue: raw))
        rebuildMenu()
    }

    @objc func selectSpecies(_ sender: NSMenuItem) {
        guard let pet = cohort?.pets[safe: sender.tag],
              let raw = sender.representedObject as? String,
              let species = PetSpecies(rawValue: raw) else { return }
        cohort?.setPookie(PookieConfig(species: species, coat: pet.pookie.coat), at: sender.tag)
        rebuildMenu()
    }

    @objc func selectCoat(_ sender: NSMenuItem) {
        guard let pet = cohort?.pets[safe: sender.tag],
              let raw = sender.representedObject as? String,
              let coat = CatSkin(rawValue: raw) else { return }
        cohort?.setPookie(PookieConfig(species: pet.pookie.species, coat: coat), at: sender.tag)
        rebuildMenu()
    }

    @objc func selectPattern(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let pattern = PookiePattern(rawValue: raw) else { return }
        cohort?.setPattern(pattern, at: sender.tag)
        rebuildMenu()
    }

    @objc func renamePookie(_ sender: NSMenuItem) {
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

    @objc func makePookieBoss(_ sender: NSMenuItem) {
        cohort?.makeDefault(index: sender.tag)
        rebuildMenu()
    }

    @objc func selectCadence(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let cadence = TeleportCadence(rawValue: raw) else { return }
        AppConfig.shared.teleportCadence = cadence
        cohort?.applyTeleportCadence()
        rebuildMenu()
    }



    @objc func selectClickThrough(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ClickThroughMode(rawValue: raw) else { return }
        AppConfig.shared.clickThroughMode = mode
        cohort?.applyClickThroughMode()
        rebuildMenu()
    }

    @objc func toggleWander() {
        AppConfig.shared.wanderEnabled.toggle()
        for pet in cohort?.pets ?? [] {
            pet.motion.wanderEnabled = AppConfig.shared.wanderEnabled
        }
        rebuildMenu()
    }

    @objc func toggleFollowCursor() {
        AppConfig.shared.followCursor.toggle()
        for pet in cohort?.pets ?? [] {
            pet.motion.followCursor = AppConfig.shared.followCursor
        }
        rebuildMenu()
    }

    @objc func togglePerch() {
        AppConfig.shared.perchEnabled.toggle()
        cohort?.setPerching(AppConfig.shared.perchEnabled)
        rebuildMenu()
    }

    @objc func toggleJump() {
        AppConfig.shared.jumpEnabled.toggle()
        cohort?.setJumping(AppConfig.shared.jumpEnabled)
        rebuildMenu()
    }

    @objc func toggleChatty() {
        AppConfig.shared.chatty.toggle()
        cohort?.setChatty(AppConfig.shared.chatty)
        rebuildMenu()
    }

    @objc func sayHello() {
        cohort?.say(PetChatter.tapped(), style: .plain)
    }

    @objc func toggleScreenSharePrivacy() {
        AppConfig.shared.hideFromScreenShare.toggle()
        cohort?.applyScreenSharePrivacy()
        rebuildMenu()
    }

    @objc func toggleRaised() {
        guard let cohort else { return }
        cohort.isRaisedAboveEverything.toggle()
        cohort.applyRaisedAboveEverything()
        rebuildMenu()
    }

    @objc func describeState() {
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

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
