import XCTest
import Carbon.HIToolbox
@testable import Pookie

final class AppIdentityTests: XCTestCase {
    private let production = AppIdentity(bundleIdentifier: "com.pookie.pet", channel: "production", isAppBundle: true)
    private let development = AppIdentity(bundleIdentifier: "com.pookie.pet.dev", channel: "development", isAppBundle: true)

    func testOnlyExplicitMatchingProductionBundleGetsProductionServices() {
        XCTAssertTrue(production.isProduction)
        for identity in [development,
                         AppIdentity(bundleIdentifier: "com.pookie.pet", channel: nil, isAppBundle: true),
                         AppIdentity(bundleIdentifier: "com.pookie.pet", channel: "unknown", isAppBundle: true),
                         AppIdentity(bundleIdentifier: "com.pookie.pet", channel: "production", isAppBundle: false),
                         AppIdentity(bundleIdentifier: "com.other.app", channel: "production", isAppBundle: true)] {
            XCTAssertFalse(identity.isProduction)
            XCTAssertFalse(identity.allowsLoginItem)
            XCTAssertEqual(identity.defaultsSuiteName, "com.pookie.pet.dev")
        }
    }

    func testPreferenceStoreUsesStandardOnlyForTheMatchingRunningBundle() {
        XCTAssertNil(production.preferenceSuiteName(runningBundleIdentifier: "com.pookie.pet"))
        XCTAssertNil(development.preferenceSuiteName(runningBundleIdentifier: "com.pookie.pet.dev"))
        XCTAssertEqual(development.preferenceSuiteName(runningBundleIdentifier: "com.pookie.pet"), "com.pookie.pet.dev")
        XCTAssertEqual(production.preferenceSuiteName(runningBundleIdentifier: "com.pookie.pet.dev"), "com.pookie.pet")
        XCTAssertEqual(development.preferenceSuiteName(runningBundleIdentifier: nil), "com.pookie.pet.dev")
        XCTAssertEqual(development.preferenceSuiteName(runningBundleIdentifier: "com.unknown.app"), "com.pookie.pet.dev")
    }

    func testProductionKeepsExistingPreferenceAndControlLocations() {
        XCTAssertEqual(production.displayName, "Pookie")
        XCTAssertEqual(production.defaultsSuiteName, "com.pookie.pet")
        XCTAssertEqual(production.supportDirectory.lastPathComponent, "Pookie")
        XCTAssertEqual(production.sayNotification.rawValue, "com.pookie.pet.say")
        XCTAssertEqual(production.socketPath(environment: [:]), production.supportDirectory.path + "/control.sock")
        XCTAssertEqual(production.portPath(environment: [:]), production.supportDirectory.path + "/port")
    }

    func testDevelopmentIsVisiblyMarkedInTheMenuBar() {
        XCTAssertEqual(production.statusItemTitle, "")
        XCTAssertEqual(development.statusItemTitle, "Dev")
    }

    func testDevelopmentHasDistinctPathsNotificationsAndShortcuts() {
        XCTAssertEqual(development.displayName, "Pookie Dev")
        XCTAssertNotEqual(production.supportDirectory, development.supportDirectory)
        XCTAssertNotEqual(production.socketPath(environment: [:]), development.socketPath(environment: [:]))
        XCTAssertNotEqual(production.portPath(environment: [:]), development.portPath(environment: [:]))
        XCTAssertNotEqual(production.sayNotification, development.sayNotification)
        XCTAssertEqual(production.hotKeyModifiers, UInt32(controlKey | optionKey))
        XCTAssertEqual(development.hotKeyModifiers, UInt32(controlKey | optionKey | shiftKey))
        XCTAssertEqual(development.shortcutPrefix, "control-option-shift")
    }

    func testSocketOverrideDoesNotLeaveFallbackPortInSharedDirectory() {
        let environment = ["POOKIE_CONTROL_SOCKET": "/tmp/pookie-test.sock"]
        XCTAssertEqual(development.socketPath(environment: environment), "/tmp/pookie-test.sock")
        XCTAssertEqual(development.portPath(environment: environment), "/tmp/pookie-test.sock.port")
        XCTAssertEqual(development.portPath(environment: environment.merging(["POOKIE_CONTROL_PORT": "/tmp/test.port"]) { _, new in new }), "/tmp/test.port")
    }

    func testSettingsRemainInTheirInjectedPreferenceDomain() {
        let prefix = "pookie.tests.\(UUID().uuidString)"
        let productionDefaults = UserDefaults(suiteName: prefix + ".production")!
        let devDefaults = UserDefaults(suiteName: prefix + ".development")!
        defer {
            productionDefaults.removePersistentDomain(forName: prefix + ".production")
            devDefaults.removePersistentDomain(forName: prefix + ".development")
        }
        productionDefaults.set(["cat|ginger|Pookie|plain|1"], forKey: "roster")
        productionDefaults.set(2, forKey: AppIdentity.settingsTabKey)
        let before = productionDefaults.dictionaryRepresentation()
        let developmentConfig = AppConfig(defaults: devDefaults)
        developmentConfig.quietMode = true
        devDefaults.set(1, forKey: AppIdentity.settingsTabKey)
        XCTAssertEqual(productionDefaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
        XCTAssertEqual(productionDefaults.integer(forKey: AppIdentity.settingsTabKey), 2)
        XCTAssertEqual(AppConfig(defaults: devDefaults).quietMode, true)
    }
}
