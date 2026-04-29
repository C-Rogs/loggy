import XCTest
@testable import Loggy

final class WatchActiveWorkoutSnapshotTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let original = WatchActiveWorkoutSnapshot(
            sessionId: "550e8400-e29b-41d4-a716-446655440000",
            workoutStartedAt: "2026-04-29T12:00:00Z",
            phase: .active,
            currentExerciseName: "Bench Press",
            completedSetCount: 3,
            restEndsAt: "2026-04-29T12:05:30Z",
            restStartedAt: "2026-04-29T12:05:00Z",
            healthSyncEnabled: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchActiveWorkoutSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testJSONKeysStableForWatchConnectivity() throws {
        let snap = WatchActiveWorkoutSnapshot(
            sessionId: "s1",
            workoutStartedAt: nil,
            phase: .idle,
            currentExerciseName: "Squat",
            completedSetCount: 0,
            restEndsAt: nil,
            restStartedAt: nil,
            healthSyncEnabled: false
        )
        let data = try JSONEncoder().encode(snap)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["phase"] as? String, "idle")
        XCTAssertEqual(obj["healthSyncEnabled"] as? Bool, false)
        XCTAssertEqual(obj["completedSetCount"] as? Int, 0)
    }
}
