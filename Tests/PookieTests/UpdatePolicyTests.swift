import XCTest
@testable import Pookie

final class UpdatePolicyTests: XCTestCase {
    private let production = AppIdentity(bundleIdentifier: "com.pookie.pet", channel: "production", isAppBundle: true)
    private var validInfo: [String: Any] {
        ["SUFeedURL": ReleaseInfo.feedURL.absoluteString,
         "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
         "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true,
         "SUSignedFeedFailureExpirationInterval": 0]
    }

    func testConfiguredProductionUsesNativeUpdater() {
        XCTAssertNil(UpdatePolicy.unavailableReason(identity: production, info: validInfo))
    }

    func testDevelopmentNeverStartsUpdaterEvenWithProductionMetadata() {
        let dev = AppIdentity(bundleIdentifier: "com.pookie.pet.dev", channel: "development", isAppBundle: true)
        XCTAssertNotNil(UpdatePolicy.unavailableReason(identity: dev, info: validInfo))
    }

    func testMissingPlaceholderAndMalformedKeysFailClosed() {
        for key in ["", "REPLACE_WITH_REAL_PUBLIC_KEY", "not a key", Data(repeating: 1, count: 31).base64EncodedString()] {
            var info = validInfo
            info["SUPublicEDKey"] = key
            XCTAssertNotNil(UpdatePolicy.unavailableReason(identity: production, info: info))
        }
        XCTAssertNotNil(UpdatePolicy.unavailableReason(identity: production, info: [:]))
    }

    func testUnexpectedOrInsecureFeedFailsClosed() {
        for feed in ["http://antick.github.io/pookie/appcast.xml", "https://example.com/appcast.xml", ""] {
            var info = validInfo
            info["SUFeedURL"] = feed
            XCTAssertNotNil(UpdatePolicy.unavailableReason(identity: production, info: info))
        }
    }
    func testDisablingFeedOrArchiveVerificationFailsClosed() {
        for flag in ["SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"] {
            var info = validInfo
            info[flag] = false
            XCTAssertNotNil(UpdatePolicy.unavailableReason(identity: production, info: info))
            info.removeValue(forKey: flag)
            XCTAssertNotNil(UpdatePolicy.unavailableReason(identity: production, info: info))
        }
    }

    func testSourceReleaseMetadataRequiresFeedAndArchiveSignatures() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual((info["SUSignedFeedFailureExpirationInterval"] as? NSNumber)?.doubleValue, 0)
        XCTAssertEqual(info["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertNil(UpdatePolicy.unavailableReason(identity: production, info: info))
    }

    func testFeedSignatureFailuresNeverExpire() {
        for interval: Any in [1, 1_728_000, -1, "0"] {
            var info = validInfo
            info["SUSignedFeedFailureExpirationInterval"] = interval
            XCTAssertNotNil(UpdatePolicy.unavailableReason(identity: production, info: info))
        }
        var missing = validInfo
        missing.removeValue(forKey: "SUSignedFeedFailureExpirationInterval")
        XCTAssertNotNil(UpdatePolicy.unavailableReason(identity: production, info: missing))
    }

}
