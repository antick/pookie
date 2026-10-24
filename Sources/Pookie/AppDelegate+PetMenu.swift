import AppKit

extension AppDelegate {
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

    @objc func togglePetHidden(_ sender: NSMenuItem) {
        guard let pet = cohort?.pets[safe: sender.tag] else { return }
        cohort?.setHidden(!pet.isHiddenByUser, at: sender.tag)
        rebuildMenu()
    }

    @objc func removePookie(_ sender: NSMenuItem) {
        cohort?.removePet(at: sender.tag)
        rebuildMenu()
    }

    @objc func bringHomePet(_ sender: NSMenuItem) {
        guard let pet = cohort?.pets[safe: sender.tag] else { return }
        pet.resetPosition()
        // Bringing one home also shows it: asking for a pet you cannot see would
        // otherwise look like nothing happened.
        if pet.isHiddenByUser {
            cohort?.setHidden(false, at: sender.tag)
            rebuildMenu()
        }
    }

}
