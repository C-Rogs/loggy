import Foundation
import GRDB

public final class NextExerciseSuggestionService: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    /// Most common exercise that follows `afterExerciseId` in completed sessions (same session, next display_order).
    public func suggestFollowing(afterExerciseId: String?, excludingExerciseIds: Set<String>) throws -> ExerciseSummary? {
        try pool.read { db in
            if let after = afterExerciseId {
                if let row = try Row.fetchOne(
                    db,
                    sql: """
                        WITH pairs AS (
                            SELECT wse2.exercise_id AS to_id, COUNT(*) AS cnt
                            FROM workout_session_exercise wse1
                            JOIN workout_session_exercise wse2
                              ON wse2.workout_session_id = wse1.workout_session_id
                             AND wse2.display_order = wse1.display_order + 1
                            JOIN workout_session ws ON ws.id = wse1.workout_session_id
                            WHERE wse1.exercise_id = ?
                              AND wse1.deleted_at IS NULL AND wse2.deleted_at IS NULL
                              AND ws.status = 'completed' AND ws.deleted_at IS NULL
                            GROUP BY wse2.exercise_id
                        )
                        SELECT e.id, e.display_name, e.exercise_mode, e.is_custom, e.primary_muscle_group
                        FROM pairs p
                        JOIN exercise e ON e.id = p.to_id AND e.deleted_at IS NULL
                        ORDER BY p.cnt DESC
                        LIMIT 1
                    """,
                    arguments: [after]
                ) {
                    let id: String = row["id"]
                    if excludingExerciseIds.contains(id) {
                        return try Self.popularFallback(db: db, excluding: excludingExerciseIds)
                    }
                    return Self.mapSummary(row)
                }
            }
            return try Self.popularFallback(db: db, excluding: excludingExerciseIds)
        }
    }

    private static func popularFallback(db: Database, excluding: Set<String>) throws -> ExerciseSummary? {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT e.id, e.display_name, e.exercise_mode, e.is_custom, e.primary_muscle_group, COUNT(*) AS c
                FROM workout_session_exercise wse
                JOIN workout_session ws ON ws.id = wse.workout_session_id
                JOIN exercise e ON e.id = wse.exercise_id AND e.deleted_at IS NULL
                WHERE ws.status = 'completed' AND ws.deleted_at IS NULL AND wse.deleted_at IS NULL
                GROUP BY e.id, e.display_name, e.exercise_mode, e.is_custom, e.primary_muscle_group
                ORDER BY c DESC
                LIMIT 12
            """
        )
        for row in rows {
            let id: String = row["id"]
            if !excluding.contains(id) { return Self.mapSummary(row) }
        }
        if let row = try Row.fetchOne(
            db,
            sql: """
                SELECT id, display_name, exercise_mode, is_custom, primary_muscle_group
                FROM exercise
                WHERE deleted_at IS NULL
                ORDER BY sort_name COLLATE NOCASE ASC
                LIMIT 1
            """
        ) {
            return Self.mapSummary(row)
        }
        return nil
    }

    private static func mapSummary(_ row: Row) -> ExerciseSummary {
        let custom: Int64 = row["is_custom"]
        return ExerciseSummary(
            id: row["id"],
            displayName: row["display_name"],
            exerciseMode: ExerciseMode(rawValue: row["exercise_mode"]) ?? .weightReps,
            isCustom: custom == 1,
            primaryMuscleGroup: row["primary_muscle_group"]
        )
    }
}
