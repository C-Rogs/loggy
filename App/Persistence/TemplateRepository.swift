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

    public func createTemplate(fromSessionId sessionId: String) throws -> String {
        let templateId = UUID().uuidString
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            guard let status: String = try String.fetchOne(
                db,
                sql: "SELECT status FROM workout_session WHERE id = ? AND deleted_at IS NULL",
                arguments: [sessionId]
            ), status == WorkoutSessionStatus.completed.rawValue
            else {
                throw TemplateRepositoryError.sessionNotCompleted
            }

            let sessionTitle: String? = try String.fetchOne(
                db,
                sql: "SELECT title FROM workout_session WHERE id = ?",
                arguments: [sessionId]
            )
            let baseName = (sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Workout"
            let templateName = "\(baseName) template"

            let nextTemplateOrder: Int = (try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(display_order), -1) + 1 FROM workout_template WHERE deleted_at IS NULL"
            )) ?? 0

            try db.execute(
                sql: """
                    INSERT INTO workout_template (id, name, notes, folder_name, display_order, created_at, updated_at)
                    VALUES (?, ?, NULL, NULL, ?, ?, ?)
                """,
                arguments: [templateId, templateName, nextTemplateOrder, now, now]
            )

            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT wse.exercise_id, wse.display_order, wse.notes, wse.target_rest_seconds,
                        (SELECT COUNT(*) FROM set_entry se
                         WHERE se.workout_session_exercise_id = wse.id AND se.deleted_at IS NULL) AS set_count,
                        (SELECT set_type FROM set_entry
                         WHERE workout_session_exercise_id = wse.id AND deleted_at IS NULL
                         ORDER BY set_index ASC LIMIT 1) AS first_set_type
                    FROM workout_session_exercise wse
                    WHERE wse.workout_session_id = ? AND wse.deleted_at IS NULL
                    ORDER BY wse.display_order ASC
                    """,
                arguments: [sessionId]
            )

            for r in rows {
                let exerciseId: String = r["exercise_id"]
                let order: Int = r["display_order"]
                let notes: String? = r["notes"]
                let rest: Int? = {
                    if let v: Int = r["target_rest_seconds"] { return v }
                    if let v: Int64 = r["target_rest_seconds"] { return Int(v) }
                    return nil
                }()
                let setCountRaw: Int = {
                    if let v: Int = r["set_count"] { return v }
                    if let v: Int64 = r["set_count"] { return Int(v) }
                    return 0
                }()
                let count = max(setCountRaw, 1)
                let firstType: String? = r["first_set_type"]
                let setType = SetType(rawValue: firstType ?? "") ?? .normal

                let rowId = UUID().uuidString
                try db.execute(
                    sql: """
                        INSERT INTO workout_template_exercise (
                            id, workout_template_id, exercise_id, block_key, display_order,
                            target_set_count, target_rep_min, target_rep_max, target_weight_kg,
                            target_duration_seconds, target_distance_km, default_set_type, default_rest_seconds,
                            notes, created_at, updated_at
                        ) VALUES (?, ?, ?, NULL, ?, ?, NULL, NULL, NULL, NULL, NULL, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        rowId, templateId, exerciseId, order, count, setType.rawValue, rest ?? 90, notes, now, now
                    ]
                )
            }
        }
        return templateId
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
                    SELECT e.id, e.display_name, e.exercise_mode, e.is_custom, e.primary_muscle_group
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
                    isCustom: (row["is_custom"] as Int?) == 1,
                    primaryMuscleGroup: row["primary_muscle_group"]
                )
            }
        }
    }
}

public enum TemplateRepositoryError: Error {
    case sessionNotCompleted
}
