import AppKit
import Sparkle

/// Reject an incomplete release before Sparkle can start any background checks.
/// Archive signatures and installed-update validation remain Sparkle's job.
enum UpdatePolicy {
    static func unavailableReason(identity: AppIdentity, info: [String: Any]) -> String? {
        guard identity.isProduction else { return "Updates are disabled in Pookie Dev." }
        guard info["SUFeedURL"] as? String == ReleaseInfo.feedURL.absoluteString else {
            return "This copy has no valid production update feed."
        }
        guard let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32 else {
            return "This copy has no valid update signing key."
        }
        guard info["SURequireSignedFeed"] as? Bool == true,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true else {
            return "This copy does not require signed update metadata and archives."
        }
        guard let expiration = info["SUSignedFeedFailureExpirationInterval"] as? NSNumber,
              expiration.doubleValue == ReleaseInfo.feedSignatureFailureExpirationInterval else {
            return "This copy allows update metadata verification to expire."
        }
        return nil
    }
}

/// Keeps Sparkle's standard macOS UI and its preference handling in one place.
final class UpdateController: NSObject {
    private var controller: SPUStandardUpdaterController?
    private(set) var unavailableReason: String?

    init(identity: AppIdentity = .current, bundle: Bundle = .main) {
        unavailableReason = UpdatePolicy.unavailableReason(identity: identity, info: bundle.infoDictionary ?? [:])
        super.init()
        guard unavailableReason == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        do {
            try controller.updater.start()
            self.controller = controller
        } catch {
            unavailableReason = "Updates could not start: \(error.localizedDescription)"
            Log.info(unavailableReason!)
        }
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }
    var isEnabled: Bool { controller != nil }
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }
}
