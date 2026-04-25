import Foundation
import GRDB

enum SeedDatabase {
    static func seedIfNeeded(pool: DatabasePool) throws {
        try pool.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exercise") ?? 0
            guard count == 0 else { return }

            let now = ISO8601UTC.string(from: Date())
            func insertExercise(id: String, canonical: String, display: String, mode: ExerciseMode) throws {
                try db.execute(
                    sql: """
                        INSERT INTO exercise (
                            id, canonical_name, display_name, exercise_mode, equipment_type,
                            primary_muscle_group, secondary_muscle_groups_json, is_custom, sort_name,
                            created_at, updated_at
                        ) VALUES (?, ?, ?, ?, NULL, NULL, '[]', 0, ?, ?, ?)
                    """,
                    arguments: [id, canonical, display, mode.rawValue, display.lowercased(), now, now]
                )
                try db.execute(
                    sql: """
                        INSERT INTO exercise_alias (id, exercise_id, alias, normalized_alias, created_at)
                        VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [UUID().uuidString, id, display, display.lowercased(), now]
                )
            }

            try insertExercise(
                id: UUID().uuidString,
                canonical: "squat (barbell)",
                display: "Squat (Barbell)",
                mode: .weightReps
            )
            try insertExercise(
                id: UUID().uuidString,
                canonical: "bench press (barbell)",
                display: "Bench Press (Barbell)",
                mode: .weightReps
            )
            try insertExercise(
                id: UUID().uuidString,
                canonical: "deadlift (barbell)",
                display: "Deadlift (Barbell)",
                mode: .weightReps
            )
            try insertExercise(
                id: UUID().uuidString,
                canonical: "pull up",
                display: "Pull Up",
                mode: .bodyweightReps
            )
            try insertExercise(
                id: UUID().uuidString,
                canonical: "leg press",
                display: "Leg Press",
                mode: .weightReps
            )
        }
    }
}
