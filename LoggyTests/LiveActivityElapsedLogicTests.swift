import XCTest
@testable import Loggy

final class LiveActivityElapsedLogicTests: XCTestCase {
    func testElapsedUsesAnchorWhenPresent() {
        let start = Date(timeIntervalSince1970: 10_000)
        let now = Date(timeIntervalSince1970: 10_060)
        XCTAssertEqual(
            LiveActivityElapsedLogic.elapsedDisplaySeconds(now: now, workoutStartedAt: start, fallbackElapsedSeconds: 999),
            60
        )
    }

    func testElapsedFallsBackWhenNoAnchor() {
        let now = Date()
        XCTAssertEqual(
            LiveActivityElapsedLogic.elapsedDisplaySeconds(now: now, workoutStartedAt: nil, fallbackElapsedSeconds: 120),
            120
        )
    }

    func testElapsedClampsNegativeSkew() {
        let start = Date().addingTimeInterval(300)
        XCTAssertEqual(
            LiveActivityElapsedLogic.elapsedDisplaySeconds(now: Date(), workoutStartedAt: start, fallbackElapsedSeconds: 10),
            0
        )
    }

    func testElapsedCapsAbsurdDuration() {
        let start = Date().addingTimeInterval(-Double(LiveActivityElapsedLogic.maxDisplayElapsedSeconds + 3600))
        let sec = LiveActivityElapsedLogic.elapsedDisplaySeconds(
            now: Date(),
            workoutStartedAt: start,
            fallbackElapsedSeconds: 0
        )
        XCTAssertEqual(sec, LiveActivityElapsedLogic.maxDisplayElapsedSeconds)
    }

    func testSanitizedStartDropsFarFuture() {
        let ref = Date(timeIntervalSince1970: 100_000)
        let skew = ref.addingTimeInterval(200)
        XCTAssertNil(LiveActivityElapsedLogic.sanitizedWorkoutStartedAt(skew, referenceNow: ref))
    }

    func testSanitizedStartKeepsNearFuture() {
        let ref = Date(timeIntervalSince1970: 100_000)
        let ok = ref.addingTimeInterval(60)
        XCTAssertEqual(
            LiveActivityElapsedLogic.sanitizedWorkoutStartedAt(ok, referenceNow: ref),
            ok
        )
    }

    func testRestPushSignatureWallClockStablePerTick() {
        let end = Date(timeIntervalSince1970: 50_000)
        let s1 = LiveActivityElapsedLogic.restPushSignature(timerId: "t1", restEndsAt: end, legacyRemainingSeconds: nil)
        let s2 = LiveActivityElapsedLogic.restPushSignature(timerId: "t1", restEndsAt: end, legacyRemainingSeconds: nil)
        XCTAssertEqual(s1, s2)
        XCTAssertTrue(s1.hasPrefix("w|t1|"))
    }

    func testRestPushSignatureChangesWhenTimerReplaced() {
        let a = LiveActivityElapsedLogic.restPushSignature(
            timerId: "t1",
            restEndsAt: Date(timeIntervalSince1970: 100),
            legacyRemainingSeconds: nil
        )
        let b = LiveActivityElapsedLogic.restPushSignature(
            timerId: "t2",
            restEndsAt: Date(timeIntervalSince1970: 100),
            legacyRemainingSeconds: nil
        )
        XCTAssertNotEqual(a, b)
    }

    func testLegacyBucketDoesNotChangeWithinBucket() {
        let step = LiveActivityElapsedLogic.legacyRestPushBucketSeconds
        let a = LiveActivityElapsedLogic.restPushSignature(timerId: nil, restEndsAt: nil, legacyRemainingSeconds: step + 2)
        let b = LiveActivityElapsedLogic.restPushSignature(timerId: nil, restEndsAt: nil, legacyRemainingSeconds: step + 1)
        XCTAssertEqual(a, b)
    }

    func testLegacyBucketChangesAcrossBoundary() {
        let step = LiveActivityElapsedLogic.legacyRestPushBucketSeconds
        let a = LiveActivityElapsedLogic.restPushSignature(timerId: nil, restEndsAt: nil, legacyRemainingSeconds: step)
        let b = LiveActivityElapsedLogic.restPushSignature(timerId: nil, restEndsAt: nil, legacyRemainingSeconds: step - 1)
        XCTAssertNotEqual(a, b)
    }

    func testWallClockPreferredOverLegacy() {
        let wall = LiveActivityElapsedLogic.restPushSignature(
            timerId: "x",
            restEndsAt: Date(timeIntervalSince1970: 1),
            legacyRemainingSeconds: 99
        )
        XCTAssertTrue(wall.hasPrefix("w|x|"))
    }
}
