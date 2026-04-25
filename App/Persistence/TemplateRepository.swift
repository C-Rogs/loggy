import Foundation
import GRDB

public final class TemplateRepository: TemplateRepositoryProtocol {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func listTemplates() throws -> [WorkoutTemplateSummary] {
        try pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, name, notes
                    FROM workout_template
                    WHERE deleted_at IS NULL
                    ORDER BY display_order ASC, name COLLATE NOCASE ASC
                """
            ).map { row in
                WorkoutTemplateSummary(id: row["id"], name: row["name"], notes: row["notes"])
            }
        }
    }

    public func createTemplate(name: String) throws -> String {
        let id = UUID().uuidString
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            let nextOrder: Int = (try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(display_order), -1) + 1 FROM workout_template WHERE deleted_at IS NULL"
            )) ?? 0
            try db.execute(
                sql: """
                    INSERT INTO workout_template (id, name, notes, folder_name, display_order, created_at, updated_at)
                    VALUES (?, ?, NULL, NULL, ?, ?, ?)
                """,
                arguments: [id, name, nextOrder, now, now]
            )
        }
        return id
    }

    public func deleteTemplate(id: String) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            try db.execute(
                sql: "UPDATE workout_template SET deleted_at = ?, updated_at = ? WHERE id = ?",
                arguments: [now, now, id]
            )
        }
    }

    public func addExerciseToTemplate(templateId: String, exerciseId: String) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            let nextOrder: Int = (try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(display_order), -1) + 1 FROM workout_template_exercise WHERE workout_template_id = ? AND deleted_at IS NULL",
                arguments: [templateId]
            )) ?? 0
            let rowId = UUID().uuidString
            try db.execute(
                sql: """
                    INSERT INTO workout_template_exercise (
                        id, workout_template_id, exercise_id, block_key, display_order,
                        target_set_count, target_rep_min, target_rep_max, target_weight_kg,
                        target_duration_seconds, target_distance_km, default_set_type, default_rest_seconds,
                        notes, created_at, updated_at
                    ) VALUES (?, ?, ?, NULL, ?, 3, NULL, NULL, NULL, NULL, NULL, 'normal', 90, NULL, ?, ?)
                """,
                arguments: [rowId, templateId, exerciseId, nextOrder, now, now]
            )
        }
    }

    public func listTemplateExercises(templateId: String) throws -> [ExerciseSummary] {
        try pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.id, e.display_name, e.exercise_mode, e.is_custom
                    FROM workout_template_exercise te
                    JOIN exercise e ON e.id = te.exercise_id
                    WHERE te.workout_template_id = ? AND te.deleted_at IS NULL
                    ORDER BY te.display_order ASC
                """,
                arguments: [templateId]
            ).map { row in
                ExerciseSummary(
                    id: row["id"],
                    displayName: row["display_name"],
                    exerciseMode: ExerciseMode(rawValue: row["exercise_mode"]) ?? .weightReps,
                    isCustom: (row["is_custom"] as Int?) == 1
                )
            }
        }
    }
}
