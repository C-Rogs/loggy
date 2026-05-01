import XCTest
@testable import Loggy

final class HeartRateZoneServiceTests: XCTestCase {
    func testHRRFractionMidRange() {
        let p = HeartRateProfile(maxBpm: 200, restBpm: 60)
        // 130 bpm -> (130-60)/(200-60) = 0.5 -> Z1 boundary actually 0.5 < 0.6 -> Z1
        XCTAssertEqual(HeartRateZoneMath.hrrFraction(bpm: 130, profile: p) ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(HeartRateZoneMath.zone(bpm: 130, profile: p), .z1)
    }

    func testHRRZoneBuckets() {
        let p = HeartRateProfile(maxBpm: 200, restBpm: 60)
        // 60% threshold -> 60 + 0.60 * 140 = 144
        XCTAssertEqual(HeartRateZoneMath.zone(bpm: 144, profile: p), .z2)
        // 70% threshold -> 158
        XCTAssertEqual(HeartRateZoneMath.zone(bpm: 158, profile: p), .z3)
        // 80% threshold -> 172
        XCTAssertEqual(HeartRateZoneMath.zone(bpm: 172, profile: p), .z4)
        // 90% threshold -> 186
        XCTAssertEqual(HeartRateZoneMath.zone(bpm: 186, profile: p), .z5)
    }

    func testRestEqualOrAboveMaxYieldsNil() {
        let degenerate = HeartRateProfile(maxBpm: 100, restBpm: 110)
        XCTAssertNil(HeartRateZoneMath.hrrFraction(bpm: 120, profile: degenerate))
        XCTAssertNil(HeartRateZoneMath.zone(bpm: 120, profile: degenerate))
    }

    func testEffortScoreAveragesOverWindow() {
        let p = HeartRateProfile(maxBpm: 200, restBpm: 60)
        let samples: [HeartRateSamplePoint] = [
            HeartRateSamplePoint(date: Date(), bpm: 130),
            HeartRateSamplePoint(date: Date().addingTimeInterval(10), bpm: 158),
        ]
        // (0.5 + 0.7) / 2 = 0.6
        XCTAssertEqual(HeartRateZoneMath.effortScore(samples: samples, profile: p) ?? 0, 0.6, accuracy: 0.0001)
    }

    func testDefaultMaxBpm() {
        XCTAssertEqual(HeartRateZoneMath.defaultMaxBpm(forAgeYears: 30), 190)
        // Age 200 -> floor at 120 to keep zones meaningful for the elderly.
        XCTAssertEqual(HeartRateZoneMath.defaultMaxBpm(forAgeYears: 200), 120)
    }
}
