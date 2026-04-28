import XCTest
@testable import Loggy

final class LoggyWorkoutDeepLinkTests: XCTestCase {
    func testParseCompleteSet() {
        let u = URL(string: "loggy://workout/live-action?op=complete&sid=s1&wse=w1&set=set1")!
        let p = LoggyWorkoutDeepLink.parse(u)
        XCTAssertEqual(p?.op, .complete)
        XCTAssertEqual(p?.sessionId, "s1")
        XCTAssertEqual(p?.wse, "w1")
        XCTAssertEqual(p?.setId, "set1")
        XCTAssertNil(p?.delta)
    }

    func testParseWeightDelta() {
        let u = URL(string: "loggy://workout/live-action?op=weight_delta&sid=s2&set=abc&d=-2.5")!
        let p = LoggyWorkoutDeepLink.parse(u)
        XCTAssertEqual(p?.op, .weightDelta)
        XCTAssertEqual(p?.sessionId, "s2")
        XCTAssertEqual(p?.setId, "abc")
        XCTAssertEqual(p?.delta, -2.5)
    }

    func testRoundTripActionURL() {
        let u = LoggyWorkoutDeepLink.actionURL(
            sessionId: "sid",
            op: .skipRest,
            wse: nil,
            setId: nil,
            delta: nil
        )
        XCTAssertNotNil(u)
        let p = LoggyWorkoutDeepLink.parse(u!)
        XCTAssertEqual(p?.op, .skipRest)
        XCTAssertEqual(p?.sessionId, "sid")
    }

    func testRejectWrongScheme() {
        let u = URL(string: "https://example.com/workout/live-action?op=complete&sid=x")!
        XCTAssertNil(LoggyWorkoutDeepLink.parse(u))
    }

    func testSessionIdRoundTripThroughActionURL() {
        let u = LoggyWorkoutDeepLink.actionURL(
            sessionId: "session-abc",
            op: .complete,
            wse: "wse1",
            setId: "set1",
            delta: nil
        )
        let p = LoggyWorkoutDeepLink.parse(u!)
        XCTAssertEqual(p?.sessionId, "session-abc")
        XCTAssertEqual(p?.wse, "wse1")
        XCTAssertEqual(p?.setId, "set1")
    }
}
