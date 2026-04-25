import Foundation
import GRDB

/// Minimal PR recompute: stores `max_weight` PR per exercise touched by the session.
final class PRService: Sendable {
    func recomputeForSession(pool: DatabasePool, sessionId: String) throws {
        try pool.write { db in
            try recomputeForSession(db: db, sessionId: sessionId)
        }
    }

    func recomputeForSession(db: Database, sessionId: String) throws {
            let exerciseIds = try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT wse.exercise_id
                    FROM workout_session_exercise wse
                    WHERE wse.workout_session_id = ? AND wse.deleted_at IS NULL
                """,
                arguments: [sessionId]
            )

            let now = ISO8601UTC.string(from: Date())

            for exerciseId in exerciseIds {
                try db.execute(
                    sql: "DELETE FROM personal_record WHERE exercise_id = ? AND metric_type = 'max_weight'",
                    arguments: [exerciseId]
                )

                guard let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT se.id as set_id, ws.id as workout_id, se.weight_kg as w, se.completed_at as ca
                        FROM set_entry se
                        JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                        JOIN workout_session ws ON ws.id = wse.workout_session_id
                        WHERE wse.exercise_id = ?
                          AND se.status = 'completed'
                          AND se.weight_kg IS NOT NULL
                          AND se.deleted_at IS NULL
                          AND wse.deleted_at IS NULL
                          AND ws.deleted_at IS NULL
                          AND ws.status = 'completed'
                        ORDER BY se.weight_kg DESC, se.completed_at DESC
                        LIMIT 1
                    """,
                    arguments: [exerciseId]
                ) else { continue }

                let best: Double = row["w"]
                let setId: String = row["set_id"]
                let wsId: String = row["workout_id"]
                let achievedAt: String = row["ca"]

                try db.execute(
                    sql: """
                        INSERT INTO personal_record (
                            id, exercise_id, metric_type, metric_value,
                            source_set_entry_id, source_workout_session_id, achieved_at, created_at
                        ) VALUES (?, ?, 'max_weight', ?, ?, ?, ?, ?)
                    """,
                    arguments: [UUID().uuidString, exerciseId, best, setId, wsId, achievedAt, now]
                )
            }
    }
}
