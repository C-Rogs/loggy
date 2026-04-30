import XCTest
@testable import Loggy

final class RestTimerServiceTests: XCTestCase {
    func testRemainingSecondsNilWhenNoEnd() {
        XCTAssertNil(RestTimerService.remainingSeconds(endsAt: nil, now: Date()))
    }

    func testRemainingSecondsZeroAtOrAfterEnd() {
        let now = Date()
        XCTAssertEqual(RestTimerService.remainingSeconds(endsAt: now, now: now), 0)
        XCTAssertEqual(RestTimerService.remainingSeconds(endsAt: now.addingTimeInterval(-1), now: now), 0)
    }

    func testRemainingSecondsCountsDown() {
        let now = Date()
        let end = now.addingTimeInterval(90.7)
        XCTAssertEqual(RestTimerService.remainingSeconds(endsAt: end, now: now), 90)
    }
}
