import GRDB
import XCTest
@testable import Loggy

final class MuscleGroupStatsRepositoryTests: XCTestCase {
    func testMuscleCountsUseLoggedExercisePrimaryMuscle() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("loggy-muscle-stats-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: url.path, configuration: config)
        try AppMigrator().migrate(pool)

        let chestId = UUID().uuidString
        let backId = UUID().uuidString
        let sessionId = UUID().uuidString
        let wseId = UUID().uuidString
        let setId = UUID().uuidString
        let now = ISO8601UTC.string(from: Date())

        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO exercise (id, canonical_name, display_name, exercise_mode, equipment_type,
                        primary_muscle_group, secondary_muscle_groups_json, is_custom, sort_name, created_at, updated_at)
                    VALUES (?, 'bench', 'Bench', 'weight_reps', NULL, 'chest', '[]', 0, 'bench', ?, ?)
                    """,
                arguments: [chestId, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO exercise (id, canonical_name, display_name, exercise_mode, equipment_type,
                        primary_muscle_group, secondary_muscle_groups_json, is_custom, sort_name, created_at, updated_at)
                    VALUES (?, 'row', 'Row', 'weight_reps', NULL, 'upper back', '[]', 0, 'row', ?, ?)
                    """,
                arguments: [backId, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO workout_session (id, title, notes, started_at, ended_at, status, source,
                        total_volume_kg_cache, total_set_count_cache, total_rep_count_cache, created_at, updated_at)
                    VALUES (?, NULL, NULL, ?, ?, 'completed', 'manual', 0, 0, 0, ?, ?)
                    """,
                arguments: [sessionId, now, now, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO workout_session_exercise (
                        id, workout_session_id, exercise_id, block_id, display_order, notes,
                        exercise_mode, target_rest_seconds, is_collapsed, created_at, updated_at)
                    VALUES (?, ?, ?, NULL, 0, NULL, 'weight_reps', 90, 0, ?, ?)
                    """,
                arguments: [wseId, sessionId, chestId, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO set_entry (
                        id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                        weight_kg, reps, completed_at, created_at, updated_at)
                    VALUES (?, ?, ?, 0, 'normal', 'completed', 50, 10, ?, ?, ?)
                    """,
                arguments: [setId, wseId, backId, now, now, now]
            )
        }

        let repo = WorkoutSessionRepository(pool: pool)
        let rows = try repo.completedSetCountsByPrimaryMuscle(sinceDaysAgo: nil)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].muscleSlug, "upper back")
        XCTAssertEqual(rows[0].completedSetCount, 1)
    }
}
