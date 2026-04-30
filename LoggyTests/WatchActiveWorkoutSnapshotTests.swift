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
            healthSyncEnabled: true,
            watchRunsHealthKitSession: true,
            watchConnectivitySchemaVersion: WatchActiveWorkoutSnapshot.currentWatchConnectivitySchemaVersion
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
        XCTAssertEqual(obj["watchConnectivitySchemaVersion"] as? Int, WatchActiveWorkoutSnapshot.currentWatchConnectivitySchemaVersion)
    }

    func testDecodeLegacyJSONWithoutSchemaVersion() throws {
        let json = """
        {"sessionId":"legacy","workoutStartedAt":null,"phase":"active","currentExerciseName":"x","completedSetCount":0,"restEndsAt":null,"restStartedAt":null,"healthSyncEnabled":true}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(WatchActiveWorkoutSnapshot.self, from: data)
        XCTAssertEqual(decoded.watchConnectivitySchemaVersion, 1)
    }

    func testWatchRunsHealthKitSessionTriStateRoundTrip() throws {
        let explicitFalse = WatchActiveWorkoutSnapshot(
            sessionId: "s2",
            workoutStartedAt: nil,
            phase: .active,
            currentExerciseName: "Pull-up",
            completedSetCount: 1,
            restEndsAt: nil,
            restStartedAt: nil,
            healthSyncEnabled: true,
            watchRunsHealthKitSession: false
        )
        let dataFalse = try JSONEncoder().encode(explicitFalse)
        let decodedFalse = try JSONDecoder().decode(WatchActiveWorkoutSnapshot.self, from: dataFalse)
        XCTAssertEqual(decodedFalse.watchRunsHealthKitSession, false)

        let omit = WatchActiveWorkoutSnapshot(
            sessionId: "s2",
            workoutStartedAt: nil,
            phase: .active,
            currentExerciseName: "Pull-up",
            completedSetCount: 1,
            restEndsAt: nil,
            restStartedAt: nil,
            healthSyncEnabled: true
        )
        let dataOmit = try JSONEncoder().encode(omit)
        let decodedOmit = try JSONDecoder().decode(WatchActiveWorkoutSnapshot.self, from: dataOmit)
        XCTAssertNil(decodedOmit.watchRunsHealthKitSession)
    }
}

// MARK: - Manual device QA (Watch integration)
// Physical Watch + iPhone: start workout with Health sync on; confirm live BPM on iPhone within ~25s;
// background phone and wake Watch from sleep; finish workout and verify a single Strength Training workout in Health.
