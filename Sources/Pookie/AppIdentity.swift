import Foundation
import Carbon.HIToolbox

/// A bundle must explicitly opt into production. CLI and unknown bundles stay
/// separate, so trying a local build cannot rewrite an installed pet's desk.
struct AppIdentity {
    enum Channel: String { case production, development }
    static let productionBundleIdentifier = "com.pookie.pet"
    static let developmentBundleIdentifier = "com.pookie.pet.dev"
    static let channelKey = "PookieChannel"
    static let settingsTabKey = "settingsTab"
    static let current = AppIdentity(bundle: .main)

    let isProduction: Bool

    init(bundle: Bundle) {
        self.init(bundleIdentifier: bundle.bundleIdentifier,
                  channel: bundle.object(forInfoDictionaryKey: Self.channelKey) as? String,
                  isAppBundle: bundle.bundleURL.pathExtension == "app")
    }

    init(bundleIdentifier: String?, channel: String?, isAppBundle: Bool) {
        isProduction = isAppBundle && bundleIdentifier == Self.productionBundleIdentifier && channel == Channel.production.rawValue
    }

    var bundleIdentifier: String { isProduction ? Self.productionBundleIdentifier : Self.developmentBundleIdentifier }
    var statusItemTitle: String { isProduction ? "" : "Dev" }
    var displayName: String { isProduction ? "Pookie" : "Pookie Dev" }
    var defaultsSuiteName: String { bundleIdentifier }
    var defaults: UserDefaults {
        guard let suite = preferenceSuiteName(runningBundleIdentifier: Bundle.main.bundleIdentifier) else {
            return .standard
        }
        guard let defaults = UserDefaults(suiteName: suite) else {
            // Falling back to standard could expose another channel's settings.
            preconditionFailure("Could not open isolated preferences for \(suite)")
        }
        return defaults
    }

    func preferenceSuiteName(runningBundleIdentifier: String?) -> String? {
        // Foundation rejects an explicit suite matching the current app domain.
        runningBundleIdentifier == defaultsSuiteName ? nil : defaultsSuiteName
    }
    var allowsLoginItem: Bool { isProduction }
    var sayNotification: Notification.Name { Notification.Name(bundleIdentifier + ".say") }
    var shortcutPrefix: String { isProduction ? "control-option" : "control-option-shift" }
    var hotKeyModifiers: UInt32 { UInt32(controlKey | optionKey) | (isProduction ? 0 : UInt32(shiftKey)) }

    var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(displayName, isDirectory: true)
    }

    func socketPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        nonempty(environment["POOKIE_CONTROL_SOCKET"]) ?? supportDirectory.appendingPathComponent("control.sock").path
    }

    func portPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let override = nonempty(environment["POOKIE_CONTROL_PORT"]) { return override }
        // A custom socket must not overwrite the normal instance's TCP discovery.
        if let socket = nonempty(environment["POOKIE_CONTROL_SOCKET"]) { return socket + ".port" }
        return supportDirectory.appendingPathComponent("port").path
    }

    private func nonempty(_ value: String?) -> String? {
        value.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Public distribution addresses have one owner across About and update policy.
enum ReleaseInfo {
    static let feedSignatureFailureExpirationInterval: TimeInterval = 0
    static let feedURL = URL(string: "https://antick.github.io/pookie/appcast.xml")!
    static let sourceURL = URL(string: "https://github.com/antick/pookie")!
    static let licenseURL = URL(string: "https://github.com/antick/pookie/blob/main/LICENSE")!
    static let licenseName = "GNU GPL v3 or later"

    static func versionDescription(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unbundled"
        return "Version \(version) (\(build))"
    }
}
