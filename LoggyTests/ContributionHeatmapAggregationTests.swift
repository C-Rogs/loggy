import XCTest
@testable import Loggy

final class ContributionHeatmapAggregationTests: XCTestCase {
    func testDayKeyFormatsLocalCalendarDate() {
        let cal = Calendar(identifier: .gregorian)
        let comps = DateComponents(year: 2026, month: 5, day: 1)
        let date = cal.date(from: comps)!
        let key = WorkoutContributionHeatmapView.dayKey(for: date)
        // "yyyy-MM-dd" — local timezone may differ but format is stable.
        XCTAssertTrue(key.hasPrefix("2026-"))
        XCTAssertEqual(key.count, 10)
    }

    func testHumanFormatRendersLocalizedDate() {
        let key = "2026-05-01"
        let formatted = WorkoutContributionHeatmapView.formatDayKeyForHumans(key)
        XCTAssertFalse(formatted.isEmpty)
        XCTAssertNotEqual(formatted, key)
    }
}
