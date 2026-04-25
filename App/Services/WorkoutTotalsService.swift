import Foundation
import GRDB

/// Recomputes denormalized workout_session cache fields from canonical `set_entry` rows.
final class WorkoutTotalsService: Sendable {
    func recomputeCaches(pool: DatabasePool, sessionId: String) throws {
        try pool.write { db in
            try recomputeCaches(db: db, sessionId: sessionId)
        }
    }

    func recomputeCaches(db: Database, sessionId: String) throws {
            let volume: Double? = try Double.fetchOne(
                db,
                sql: """
                    SELECT SUM(COALESCE(se.weight_kg, 0) * COALESCE(CAST(se.reps AS REAL), 0))
                    FROM set_entry se
                    JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                    WHERE wse.workout_session_id = ?
                      AND se.status = 'completed'
                      AND se.deleted_at IS NULL
                      AND wse.deleted_at IS NULL
                """,
                arguments: [sessionId]
            )

            let setCount: Int = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM set_entry se
                    JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                    WHERE wse.workout_session_id = ?
                      AND se.status = 'completed'
                      AND se.deleted_at IS NULL
                      AND wse.deleted_at IS NULL
                """,
                arguments: [sessionId]
            ) ?? 0

            let repSum: Int = try Int.fetchOne(
                db,
                sql: """
                    SELECT SUM(COALESCE(se.reps, 0))
                    FROM set_entry se
                    JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                    WHERE wse.workout_session_id = ?
                      AND se.status = 'completed'
                      AND se.deleted_at IS NULL
                      AND wse.deleted_at IS NULL
                """,
                arguments: [sessionId]
            ) ?? 0

            let startedAt: String? = try String.fetchOne(
                db,
                sql: "SELECT started_at FROM workout_session WHERE id = ?",
                arguments: [sessionId]
            )
            let endedAt: String? = try String.fetchOne(
                db,
                sql: "SELECT ended_at FROM workout_session WHERE id = ?",
                arguments: [sessionId]
            )

            var durationSeconds: Int?
            if let startedAt,
               let s = ISO8601UTC.date(from: startedAt)
            {
                let end = (endedAt).flatMap(ISO8601UTC.date(from:)) ?? Date()
                durationSeconds = max(0, Int(end.timeIntervalSince(s)))
            }

            let now = ISO8601UTC.string(from: Date())
            try db.execute(
                sql: """
                    UPDATE workout_session
                    SET total_volume_kg_cache = ?,
                        total_set_count_cache = ?,
                        total_rep_count_cache = ?,
                        total_duration_seconds_cache = ?,
                        updated_at = ?
                    WHERE id = ?
                """,
                arguments: [volume ?? 0, setCount, repSum, durationSeconds, now, sessionId]
            )
    }
}
