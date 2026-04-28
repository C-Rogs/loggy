import GRDB
import XCTest
@testable import Loggy

final class ReplaceExerciseAttributionTests: XCTestCase {
    func testReplaceKeepsCompletedLoggedExerciseAndClearsPlanned() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("loggy-attrib-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: url.path, configuration: config)
        try AppMigrator().migrate(pool)

        let benchId = UUID().uuidString
        let dumbbellId = UUID().uuidString
        let sessionId = UUID().uuidString
        let wseId = UUID().uuidString
        let setDone = UUID().uuidString
        let setPlanned = UUID().uuidString
        let now = ISO8601UTC.string(from: Date())

        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO exercise (id, canonical_name, display_name, exercise_mode, equipment_type,
                        primary_muscle_group, secondary_muscle_groups_json, is_custom, sort_name, created_at, updated_at)
                    VALUES (?, 'bench press (barbell)', 'Bench Press (Barbell)', 'weight_reps', NULL, 'chest', '[]', 0, 'bench press (barbell)', ?, ?)
                    """,
                arguments: [benchId, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO exercise (id, canonical_name, display_name, exercise_mode, equipment_type,
                        primary_muscle_group, secondary_muscle_groups_json, is_custom, sort_name, created_at, updated_at)
                    VALUES (?, 'bench press (dumbbell)', 'Bench Press (Dumbbell)', 'weight_reps', NULL, 'chest', '[]', 0, 'bench press (dumbbell)', ?, ?)
                    """,
                arguments: [dumbbellId, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO workout_session (id, title, notes, started_at, ended_at, status, source,
                        total_volume_kg_cache, total_set_count_cache, total_rep_count_cache, created_at, updated_at)
                    VALUES (?, NULL, NULL, ?, NULL, 'active', 'manual', 0, 0, 0, ?, ?)
                    """,
                arguments: [sessionId, now, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO workout_session_exercise (
                        id, workout_session_id, exercise_id, block_id, display_order, notes,
                        exercise_mode, target_rest_seconds, is_collapsed, created_at, updated_at)
                    VALUES (?, ?, ?, NULL, 0, NULL, 'weight_reps', 90, 0, ?, ?)
                    """,
                arguments: [wseId, sessionId, benchId, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO set_entry (
                        id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                        weight_kg, reps, completed_at, created_at, updated_at)
                    VALUES (?, ?, ?, 0, 'normal', 'completed', 80, 5, ?, ?, ?)
                    """,
                arguments: [setDone, wseId, benchId, now, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO set_entry (
                        id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                        weight_kg, reps, completed_at, created_at, updated_at)
                    VALUES (?, ?, ?, 1, 'normal', 'planned', 80, 5, NULL, ?, ?)
                    """,
                arguments: [setPlanned, wseId, benchId, now, now]
            )
        }

        let repo = WorkoutSessionRepository(pool: pool)
        try repo.replaceSessionExercise(sessionId: sessionId, sessionExerciseId: wseId, newExerciseId: dumbbellId)

        let doneLogged: String? = try pool.read { db in
            try String.fetchOne(db, sql: "SELECT logged_exercise_id FROM set_entry WHERE id = ?", arguments: [setDone])
        }
        let plannedLogged: String? = try pool.read { db in
            try String.fetchOne(db, sql: "SELECT logged_exercise_id FROM set_entry WHERE id = ?", arguments: [setPlanned])
        }
        let plannedWeight: Double? = try pool.read { db in
            try Double.fetchOne(db, sql: "SELECT weight_kg FROM set_entry WHERE id = ?", arguments: [setPlanned])
        }
        XCTAssertEqual(doneLogged, benchId)
        XCTAssertEqual(plannedLogged, dumbbellId)
        XCTAssertNil(plannedWeight)

        let slotExercise: String? = try pool.read { db in
            try String.fetchOne(db, sql: "SELECT exercise_id FROM workout_session_exercise WHERE id = ?", arguments: [wseId])
        }
        XCTAssertEqual(slotExercise, dumbbellId)
    }
}
