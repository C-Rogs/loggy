import GRDB
import XCTest
@testable import Loggy

final class TrainingBaselineServiceTests: XCTestCase {
    func testEmptyHistoryReturnsZeros() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("loggy-baseline-\(UUID().uuidString).sqlite")
        var config = Configuration()
        config.foreignKeysEnabled = true
        var pool: DatabasePool? = try DatabasePool(path: url.path, configuration: config)
        try AppMigrator().migrate(pool!)
        let svc = TrainingBaselineService(pool: pool!)
        let snap = try svc.fetchSnapshot()
        XCTAssertEqual(snap.sumVolumeKgLast7Days, 0, accuracy: 0.001)
        XCTAssertEqual(snap.completedSessionsLast7Days, 0)
        XCTAssertNil(snap.avgWeeklyVolumeKgLast28Days)
        pool = nil
        try? FileManager.default.removeItem(at: url)
    }
}
