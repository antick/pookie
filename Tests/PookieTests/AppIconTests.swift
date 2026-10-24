import XCTest
import ImageIO
@testable import Pookie

final class AppIconTests: XCTestCase {
    func testExportWritesValidNonempty1024PixelPNGForBothChannels() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var outputs: [Data] = []
        for channel in ["production", "development"] {
            let destination = directory.appendingPathComponent(channel + ".png")
            let request = try XCTUnwrap(IconExportRequest.parse(arguments: ["Pookie", "--render-icon", destination.path, "--icon-channel", channel]))
            try AppIcon.export(to: request.path, identity: request.identity)
            let data = try Data(contentsOf: destination)
            XCTAssertGreaterThan(data.count, 10_000)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.png")
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 1024)
            XCTAssertEqual(image.height, 1024)
            outputs.append(data)
        }
        XCTAssertNotEqual(outputs[0], outputs[1], "The development badge must change the exported artwork")
    }

    func testIconChannelIsValidatedAndOnlyAffectsExport() throws {
        XCTAssertNil(try IconExportRequest.parse(arguments: ["Pookie", "--selftest"]))
        for arguments in [["Pookie", "--icon-channel", "production"],
                          ["Pookie", "--render-icon"],
                          ["Pookie", "--render-icon", "out.png", "--icon-channel", "staging"],
                          ["Pookie", "--render-icon", "out.png", "--icon-channel"]] {
            XCTAssertThrowsError(try IconExportRequest.parse(arguments: arguments))
        }
        let request = try XCTUnwrap(IconExportRequest.parse(arguments: ["Pookie", "--render-icon", "out.png", "--icon-channel", "production"]))
        XCTAssertTrue(request.identity.isProduction)
        XCTAssertFalse(AppIdentity.current.isProduction, "An export option must never change the running app's identity")
        let automatic = try XCTUnwrap(IconExportRequest.parse(arguments: ["Pookie", "--render-icon", "out.png"]))
        XCTAssertEqual(automatic.identity.isProduction, AppIdentity.current.isProduction)
    }

    func testBareExportRunsWithoutDynamicLibraryOverrides() throws {
        let executable = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("Pookie")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: destination) }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--render-icon", destination.path, "--icon-channel", "production"]
        process.environment = ["PATH": "/usr/bin:/bin"]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testExportReportsUnwritableDestination() throws {
        XCTAssertThrowsError(try AppIcon.export(to: "/no-such-pookie-test-directory/icon.png", identity: .current))
    }
}
