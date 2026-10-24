import AppKit

extension AppDelegate {
    func addReleaseItems(to menu: NSMenu) {
        let about = NSMenuItem(title: "About \(AppIdentity.current.displayName)…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        check.target = self
        check.isEnabled = updateController?.canCheckForUpdates ?? false
        check.toolTip = updateController?.unavailableReason
        menu.addItem(check)

        let automatic = NSMenuItem(title: "Automatically Check for Updates", action: #selector(toggleAutomaticUpdates), keyEquivalent: "")
        automatic.target = self
        automatic.state = updateController?.automaticallyChecksForUpdates == true ? .on : .off
        automatic.isEnabled = updateController?.isEnabled ?? false
        automatic.toolTip = updateController?.unavailableReason
        menu.addItem(automatic)
        menu.addItem(.separator())
    }

    @objc func checkForUpdates() {
        updateController?.checkForUpdates(nil)
    }

    @objc func toggleAutomaticUpdates() {
        guard let updateController, updateController.isEnabled else { return }
        updateController.automaticallyChecksForUpdates.toggle()
        rebuildMenu()
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = AppIdentity.current.displayName
        alert.informativeText = "\(ReleaseInfo.versionDescription())\n\nA little company on your desktop.\n\nCopyright © Pankaj Sanam\nLicensed under \(ReleaseInfo.licenseName)."
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "License")
        alert.addButton(withTitle: "Source Code")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertSecondButtonReturn: NSWorkspace.shared.open(ReleaseInfo.licenseURL)
        case .alertThirdButtonReturn: NSWorkspace.shared.open(ReleaseInfo.sourceURL)
        default: break
        }
    }
}
