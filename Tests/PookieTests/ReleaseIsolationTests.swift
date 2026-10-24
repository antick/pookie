import XCTest
@testable import Pookie

final class ReleaseIsolationTests: XCTestCase {
    func testBareExecutableUsesDevelopmentControlDirectory() {
        XCTAssertEqual((ControlServer.defaultDirectory as NSString).lastPathComponent, "Pookie Dev")
        XCTAssertEqual(ControlServer.defaultPortPath, ControlServer.defaultDirectory + "/port")
    }

    func testBareExecutableCannotSpeakToProductionNotificationBridge() {
        XCTAssertEqual(AppDelegate.sayNotification.rawValue, "com.pookie.pet.dev.say")
    }
}
