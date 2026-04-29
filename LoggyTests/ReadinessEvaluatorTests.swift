import XCTest
@testable import Loggy

final class ReadinessEvaluatorTests: XCTestCase {
    func testUnknownWhenNoAuthNoData() {
        let s = ReadinessSnapshot(
            sleepDurationSeconds: nil,
            hrvRecentMS: nil,
            hrvBaselineMedianMS: nil,
            hrvBaselineSampleCount: 0,
            hadSleepAuthorization: false,
            hadHRVAuthorization: false
        )
        let i = ReadinessEvaluator.evaluate(s)
        XCTAssertEqual(i.band, .unknown)
    }

    func testLowWhenVeryShortSleep() {
        let s = ReadinessSnapshot(
            sleepDurationSeconds: 4 * 3600,
            hrvRecentMS: nil,
            hrvBaselineMedianMS: nil,
            hrvBaselineSampleCount: 0,
            hadSleepAuthorization: true,
            hadHRVAuthorization: false
        )
        let i = ReadinessEvaluator.evaluate(s)
        XCTAssertEqual(i.band, .low)
    }

    func testHighWhenSolidSleepAndStrongHRV() {
        let s = ReadinessSnapshot(
            sleepDurationSeconds: 8 * 3600,
            hrvRecentMS: 55,
            hrvBaselineMedianMS: 50,
            hrvBaselineSampleCount: ReadinessEvaluator.minimumBaselineHRVSamples,
            hadSleepAuthorization: true,
            hadHRVAuthorization: true
        )
        let i = ReadinessEvaluator.evaluate(s)
        XCTAssertEqual(i.band, .high)
    }

    func testLowWhenHrvWellBelowBaseline() {
        let s = ReadinessSnapshot(
            sleepDurationSeconds: 8 * 3600,
            hrvRecentMS: 30,
            hrvBaselineMedianMS: 50,
            hrvBaselineSampleCount: ReadinessEvaluator.minimumBaselineHRVSamples,
            hadSleepAuthorization: true,
            hadHRVAuthorization: true
        )
        let i = ReadinessEvaluator.evaluate(s)
        XCTAssertEqual(i.band, .low)
    }

    func testModerateWhenMixedSignals() {
        let s = ReadinessSnapshot(
            sleepDurationSeconds: nil,
            hrvRecentMS: 50,
            hrvBaselineMedianMS: 50,
            hrvBaselineSampleCount: ReadinessEvaluator.minimumBaselineHRVSamples,
            hadSleepAuthorization: true,
            hadHRVAuthorization: true
        )
        let i = ReadinessEvaluator.evaluate(s)
        XCTAssertEqual(i.band, .moderate)
    }

    func testPersonalSleepNormsVsPopulationSameNight() {
        let personal = ReadinessSnapshot(
            sleepDurationSeconds: 4.5 * 3600,
            hrvRecentMS: nil,
            hrvBaselineMedianMS: nil,
            hrvBaselineSampleCount: 0,
            hadSleepAuthorization: true,
            hadHRVAuthorization: false,
            sleepShortThresholdHours: 4,
            sleepSolidThresholdHours: 5.5,
            usesPersonalSleepNorms: true,
            usesPersonalHRVNorms: false
        )
        let population = ReadinessSnapshot(
            sleepDurationSeconds: 4.5 * 3600,
            hrvRecentMS: nil,
            hrvBaselineMedianMS: nil,
            hrvBaselineSampleCount: 0,
            hadSleepAuthorization: true,
            hadHRVAuthorization: false
        )
        XCTAssertEqual(ReadinessEvaluator.evaluate(population).band, .low)
        XCTAssertEqual(ReadinessEvaluator.evaluate(personal).band, .moderate)
        XCTAssertTrue(ReadinessEvaluator.evaluate(personal).usesPersonalizedThresholds)
    }

    func testPersonalHRVThresholdWidensOkBand() {
        // Ratio 0.80: with population tiers it sits in the mild HRV penalty bucket (0.5 - 0.2 = 0.3 → low).
        // Personalized `lowR` can mark 0.80 as "near enough" (+0.05) so the same sample is moderate.
        let personal = ReadinessSnapshot(
            sleepDurationSeconds: nil,
            hrvRecentMS: 40,
            hrvBaselineMedianMS: 50,
            hrvBaselineSampleCount: ReadinessEvaluator.minimumBaselineHRVSamples,
            hadSleepAuthorization: true,
            hadHRVAuthorization: true,
            hrvLowRatio: 0.77,
            hrvVeryLowRatio: 0.55,
            usesPersonalSleepNorms: false,
            usesPersonalHRVNorms: true
        )
        let population = ReadinessSnapshot(
            sleepDurationSeconds: nil,
            hrvRecentMS: 40,
            hrvBaselineMedianMS: 50,
            hrvBaselineSampleCount: ReadinessEvaluator.minimumBaselineHRVSamples,
            hadSleepAuthorization: true,
            hadHRVAuthorization: true
        )
        XCTAssertEqual(ReadinessEvaluator.evaluate(population).band, .low)
        XCTAssertEqual(ReadinessEvaluator.evaluate(personal).band, .moderate)
        XCTAssertTrue(ReadinessEvaluator.evaluate(personal).usesPersonalizedThresholds)
    }
}

final class ReadinessNormsStoreTests: XCTestCase {
    func testPersonalSleepThresholdsAfterSevenNights() {
        var p = ReadinessNormsStore.Persisted()
        for i in 0..<7 {
            let key = String(format: "2026-01-%02d", 10 + i)
            p.sleepHoursByDayKey[key] = 7.2 + Double(i) * 0.02
        }
        let t = ReadinessNormsStore.personalSleepThresholds(from: p)
        XCTAssertNotNil(t)
        XCTAssertGreaterThan(t!.solid, t!.short)
    }

    func testPersonalHRVThresholdsAfterTenDays() {
        var p = ReadinessNormsStore.Persisted()
        for i in 0..<10 {
            let key = String(format: "2026-02-%02d", 1 + i)
            p.hrvRatioByDayKey[key] = 0.75 + Double(i) * 0.01
        }
        let t = ReadinessNormsStore.personalHRVThresholds(from: p)
        XCTAssertNotNil(t)
        XCTAssertLessThan(t!.veryLow, t!.low)
    }
}
