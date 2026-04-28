import Foundation
import GRDB

private final class MigrationSchemaBundleLocator: NSObject {}

struct AppMigrator {
    func migrate(_ writer: DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("schema_v1") { db in
            let bundle = Bundle(for: MigrationSchemaBundleLocator.self)
            guard let url = bundle.url(forResource: "04_DATABASE_SCHEMA", withExtension: "sql"),
                  let sql = try? String(contentsOf: url, encoding: .utf8)
            else {
                throw MigrationError("Missing bundled 04_DATABASE_SCHEMA.sql")
            }
            // Strip PRAGMA; pool enables foreign keys via configuration.
            let lines = sql.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("PRAGMA") }
            try db.execute(sql: lines.joined(separator: "\n"))
        }

        migrator.registerMigration("import_batch_v2") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS import_batch (
                    id TEXT PRIMARY KEY,
                    content_sha256 TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL,
                    source_filename TEXT
                );
            """)
        }

        migrator.registerMigration("exercise_media_v3") { db in
            let names = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('exercise')")
            if !names.contains("instruction_text") {
                try db.execute(sql: "ALTER TABLE exercise ADD COLUMN instruction_text TEXT")
            }
            if !names.contains("gif_url") {
                try db.execute(sql: "ALTER TABLE exercise ADD COLUMN gif_url TEXT")
            }

            let updates: [(String, String, String?)] = [
                (
                    "squat (barbell)",
                    "Stand with the bar on your upper back. Break at hips and knees together, descend until hip crease is below the knee, then drive up through mid-foot.",
                    "https://upload.wikimedia.org/wikipedia/commons/thumb/b/ba/Squat_%28exercise%29_-_World_Class_Athletics.jpg/440px-Squat_%28exercise%29_-_World_Class_Athletics.jpg"
                ),
                (
                    "bench press (barbell)",
                    "Retract shoulder blades, slight arch, bar over mid-chest. Touch controlled, press back toward face in an arc.",
                    "https://upload.wikimedia.org/wikipedia/commons/thumb/4/42/Bench_press_1.jpg/440px-Bench_press_1.jpg"
                ),
                (
                    "deadlift (barbell)",
                    "Hinge to the bar, brace lats, push floor away. Keep bar close; lock hips and knees together at the top.",
                    "https://upload.wikimedia.org/wikipedia/commons/thumb/6/60/Deadlift.jpg/440px-Deadlift.jpg"
                ),
                (
                    "pull up",
                    "Hang full extension, initiate with lats, drive elbows down and back. Chin clears bar without excessive kick.",
                    "https://upload.wikimedia.org/wikipedia/commons/thumb/5/5f/Pull-up_%28exercise%29.jpg/440px-Pull-up_%28exercise%29.jpg"
                ),
                (
                    "leg press",
                    "Feet shoulder-width on sled, lower under control to ~90° at knee without rounding low off pad, press without locking aggressively.",
                    nil
                )
            ]
            let now = ISO8601UTC.string(from: Date())
            for (canonical, text, url) in updates {
                if let url {
                    try db.execute(
                        sql: """
                            UPDATE exercise
                            SET instruction_text = COALESCE(instruction_text, ?),
                                gif_url = COALESCE(gif_url, ?),
                                updated_at = ?
                            WHERE canonical_name = ? AND deleted_at IS NULL
                        """,
                        arguments: [text, url, now, canonical]
                    )
                } else {
                    try db.execute(
                        sql: """
                            UPDATE exercise
                            SET instruction_text = COALESCE(instruction_text, ?),
                                updated_at = ?
                            WHERE canonical_name = ? AND deleted_at IS NULL
                        """,
                        arguments: [text, now, canonical]
                    )
                }
            }
        }

        migrator.registerMigration("hevy_library_exercises_v4") { db in
            let now = ISO8601UTC.string(from: Date())
            for row in HevyStyleExerciseCatalog.rows {
                let existing = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM exercise
                        WHERE lower(canonical_name) = lower(?) AND deleted_at IS NULL
                        """,
                    arguments: [row.canonical]
                ) ?? 0
                if existing > 0 { continue }

                let id = UUID().uuidString
                try db.execute(
                    sql: """
                        INSERT INTO exercise (
                            id, canonical_name, display_name, exercise_mode, equipment_type,
                            primary_muscle_group, secondary_muscle_groups_json, is_custom, sort_name,
                            created_at, updated_at
                        ) VALUES (?, ?, ?, ?, NULL, NULL, '[]', 0, ?, ?, ?)
                        """,
                    arguments: [id, row.canonical, row.display, row.mode.rawValue, row.display.lowercased(), now, now]
                )
                try db.execute(
                    sql: """
                        INSERT INTO exercise_alias (id, exercise_id, alias, normalized_alias, created_at)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [UUID().uuidString, id, row.display, row.display.lowercased(), now]
                )
            }
        }

        try migrator.migrate(writer)
    }
}

private struct MigrationError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
