import XCTest
@testable import Loggy

final class IntraSessionCoachTests: XCTestCase {
    func testOffReturnsNil() {
        let r = IntraSessionCoach.evaluate(
            IntraSessionCoachInput(lastSetEffort: 0.5, lastSetZone: .z2, intensity: .off, hrvLowVsBaseline: false)
        )
        XCTAssertNil(r)
    }

    func testStandardPushesWhenZoneBelowTarget() {
        let r = IntraSessionCoach.evaluate(
            IntraSessionCoachInput(lastSetEffort: 0.5, lastSetZone: .z1, intensity: .standard, hrvLowVsBaseline: false)
        )
        XCTAssertEqual(r?.tone, .push)
        XCTAssertTrue(r?.headline.contains("Z1") ?? false)
    }

    func testStandardOnTarget() {
        let r = IntraSessionCoach.evaluate(
            IntraSessionCoachInput(lastSetEffort: 0.75, lastSetZone: .z3, intensity: .standard, hrvLowVsBaseline: false)
        )
        XCTAssertEqual(r?.tone, .neutral)
    }

    func testAggressivePushesEvenAtZ3() {
        let r = IntraSessionCoach.evaluate(
            IntraSessionCoachInput(lastSetEffort: 0.75, lastSetZone: .z3, intensity: .aggressive, hrvLowVsBaseline: false)
        )
        XCTAssertEqual(r?.tone, .push)
    }

    func testHRVGateMutesPush() {
        let r = IntraSessionCoach.evaluate(
            IntraSessionCoachInput(lastSetEffort: 0.5, lastSetZone: .z1, intensity: .aggressive, hrvLowVsBaseline: true)
        )
        XCTAssertEqual(r?.tone, .recover)
        XCTAssertTrue(r?.headline.contains("HRV") ?? false)
    }

    func testTaperWhenAboveTarget() {
        let r = IntraSessionCoach.evaluate(
            IntraSessionCoachInput(lastSetEffort: 0.95, lastSetZone: .z5, intensity: .light, hrvLowVsBaseline: false)
        )
        XCTAssertEqual(r?.tone, .taper)
    }
}
