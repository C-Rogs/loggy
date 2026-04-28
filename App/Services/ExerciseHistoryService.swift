import Foundation
import GRDB

/// Maintains `exercise_history_snapshot` rows for exercises touched by a session.
final class ExerciseHistoryService: Sendable {
    func rebuildSnapshotsForSession(pool: DatabasePool, sessionId: String) throws {
        try pool.write { db in
            try rebuildSnapshotsForSession(db: db, sessionId: sessionId)
        }
    }

    func rebuildSnapshotsForSession(db: Database, sessionId: String) throws {
            let exerciseIds = try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT eid FROM (
                        SELECT DISTINCT COALESCE(se.logged_exercise_id, wse.exercise_id) AS eid
                        FROM set_entry se
                        JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                        WHERE wse.workout_session_id = ?
                          AND se.status = 'completed'
                          AND se.deleted_at IS NULL
                          AND wse.deleted_at IS NULL
                        UNION
                        SELECT wse.exercise_id AS eid
                        FROM workout_session_exercise wse
                        WHERE wse.workout_session_id = ? AND wse.deleted_at IS NULL
                    )
                """,
                arguments: [sessionId, sessionId]
            )

            let now = ISO8601UTC.string(from: Date())

            for exerciseId in exerciseIds {
                guard let last = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT ws.id as wid, se.weight_kg as w, se.reps as r, se.completed_at as ca
                        FROM set_entry se
                        JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                        JOIN workout_session ws ON ws.id = wse.workout_session_id
                        WHERE COALESCE(se.logged_exercise_id, wse.exercise_id) = ?
                          AND se.status = 'completed'
                          AND se.deleted_at IS NULL
                          AND wse.deleted_at IS NULL
                          AND ws.deleted_at IS NULL
                          AND ws.status = 'completed'
                        ORDER BY se.completed_at DESC
                        LIMIT 1
                    """,
                    arguments: [exerciseId]
                ) else { continue }

                let wid: String = last["wid"]
                let w: Double? = last["w"]
                let r: Int? = last["r"]
                let ca: String = last["ca"]

                let summary: String
                if let w, let r { summary = "{\"weight_kg\":\(w),\"reps\":\(r)}" }
                else if let w { summary = "{\"weight_kg\":\(w)}" }
                else if let r { summary = "{\"reps\":\(r)}" }
                else { summary = "{}" }

                let bestWeight: Double? = try Double.fetchOne(
                    db,
                    sql: """
                        SELECT MAX(se.weight_kg)
                        FROM set_entry se
                        JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                        JOIN workout_session ws ON ws.id = wse.workout_session_id
                        WHERE COALESCE(se.logged_exercise_id, wse.exercise_id) = ?
                          AND se.status = 'completed'
                          AND se.weight_kg IS NOT NULL
                          AND se.deleted_at IS NULL
                          AND wse.deleted_at IS NULL
                          AND ws.deleted_at IS NULL
                          AND ws.status = 'completed'
                    """,
                    arguments: [exerciseId]
                )

                let volume: Double = try Double.fetchOne(
                    db,
                    sql: """
                        SELECT SUM(COALESCE(se.weight_kg, 0) * COALESCE(CAST(se.reps AS REAL), 0))
                        FROM set_entry se
                        JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                        JOIN workout_session ws ON ws.id = wse.workout_session_id
                        WHERE COALESCE(se.logged_exercise_id, wse.exercise_id) = ?
                          AND se.status = 'completed'
                          AND se.deleted_at IS NULL
                          AND wse.deleted_at IS NULL
                          AND ws.deleted_at IS NULL
                          AND ws.status = 'completed'
                    """,
                    arguments: [exerciseId]
                ) ?? 0

                let completedCount: Int = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*)
                        FROM set_entry se
                        JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                        JOIN workout_session ws ON ws.id = wse.workout_session_id
                        WHERE COALESCE(se.logged_exercise_id, wse.exercise_id) = ?
                          AND se.status = 'completed'
                          AND se.deleted_at IS NULL
                          AND wse.deleted_at IS NULL
                          AND ws.deleted_at IS NULL
                          AND ws.status = 'completed'
                    """,
                    arguments: [exerciseId]
                ) ?? 0

                try db.execute(
                    sql: """
                        INSERT INTO exercise_history_snapshot (
                            exercise_id, last_performed_at, last_workout_session_id,
                            last_completed_set_summary_json, best_weight_kg, best_estimated_1rm_kg,
                            lifetime_volume_kg, completed_set_count, updated_at
                        ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?)
                        ON CONFLICT(exercise_id) DO UPDATE SET
                            last_performed_at = excluded.last_performed_at,
                            last_workout_session_id = excluded.last_workout_session_id,
                            last_completed_set_summary_json = excluded.last_completed_set_summary_json,
                            best_weight_kg = excluded.best_weight_kg,
                            lifetime_volume_kg = excluded.lifetime_volume_kg,
                            completed_set_count = excluded.completed_set_count,
                            updated_at = excluded.updated_at
                    """,
                    arguments: [exerciseId, ca, wid, summary, bestWeight, volume, completedCount, now]
                )
            }
    }
}
