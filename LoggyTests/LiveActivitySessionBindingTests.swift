import XCTest
@testable import Loggy

final class LiveActivitySessionBindingTests: XCTestCase {
    func testSameSessionDoesNotRequireEndBeforeStart() {
        XCTAssertFalse(
            LiveActivitySessionBinding.shouldEndBeforeStarting(existingSessionId: "s1", requestedSessionId: "s1")
        )
    }

    func testDifferentSessionRequiresEndBeforeStart() {
        XCTAssertTrue(
            LiveActivitySessionBinding.shouldEndBeforeStarting(existingSessionId: "s1", requestedSessionId: "s2")
        )
    }

    func testAcceptUpdateOnlyWhenSessionMatches() {
        XCTAssertTrue(LiveActivitySessionBinding.shouldAcceptUpdate(boundSessionId: "a", updateSessionId: "a"))
        XCTAssertFalse(LiveActivitySessionBinding.shouldAcceptUpdate(boundSessionId: "a", updateSessionId: "b"))
    }
}
