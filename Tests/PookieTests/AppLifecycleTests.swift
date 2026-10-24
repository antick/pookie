import XCTest
import AppKit
@testable import Pookie

final class AppLifecycleTests: XCTestCase {
    private func runningServer(in directory: URL) throws -> ControlServer {
        let server = ControlServer(socketPath: directory.appendingPathComponent("control.sock").path, portPath: nil)
        try server.start()
        return server
    }

    func testDeinitRemovesControlSocketEvenWithoutSayObserver() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = try runningServer(in: directory)
        let socket = directory.appendingPathComponent("control.sock").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: socket))
        var delegate: AppDelegate? = AppDelegate()
        delegate?.controlServer = server
        delegate = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: socket))
    }

    @MainActor
    func testTerminationRemovesSocketAndNotificationObservers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let delegate = AppDelegate()
        delegate.controlServer = try runningServer(in: directory)
        delegate.installSayBridge()
        delegate.installPauseObservers()
        XCTAssertNotNil(delegate.sayObserver)
        XCTAssertEqual(delegate.pauseObservers.count, 4)
        (delegate as NSApplicationDelegate).applicationWillTerminate?(Notification(name: NSApplication.willTerminateNotification))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("control.sock").path))
        XCTAssertNil(delegate.controlServer)
        XCTAssertNil(delegate.sayObserver)
        XCTAssertTrue(delegate.pauseObservers.isEmpty)
    }
}
