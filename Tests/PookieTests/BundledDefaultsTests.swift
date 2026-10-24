import XCTest
@testable import Pookie

final class BundledDefaultsTests: XCTestCase {
    func testBundledDevelopmentCanLoadPreferencesWithoutCrashing() throws {
        let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = directory.appendingPathComponent("Pookie Dev.app/Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let frameworks = contents.appendingPathComponent("Frameworks")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent("Pookie")
        try FileManager.default.copyItem(at: products.appendingPathComponent("Pookie"), to: executable)
        try FileManager.default.createSymbolicLink(at: frameworks.appendingPathComponent("Sparkle.framework"),
                                                  withDestinationURL: products.appendingPathComponent("Sparkle.framework"))
        let info: [String: Any] = [
            "CFBundleIdentifier": AppIdentity.developmentBundleIdentifier,
            "CFBundleExecutable": "Pookie", "CFBundlePackageType": "APPL",
            AppIdentity.channelKey: "development",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        let process = Process()
        process.executableURL = executable
        // Verbose initializes AppConfig before this deliberately invalid flag
        // returns. A defaults crash must not be mistaken for ordinary exit 2.
        process.arguments = ["--verbose", "--scale", "invalid-test-scale"]
        process.environment = ["PATH": "/usr/bin:/bin"]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationReason, .exit, message)
        XCTAssertEqual(process.terminationStatus, 2, message)
        XCTAssertTrue(message.contains("--scale expects"), message)
        XCTAssertFalse(message.contains("NSUserDefaults suite name"), message)
    }
}
