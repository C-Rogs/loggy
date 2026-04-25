import Foundation
import GRDB

struct AppMigrator {
    func migrate(_ writer: DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("schema_v1") { db in
            let bundle = Bundle.main
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

        try migrator.migrate(writer)
    }
}

private struct MigrationError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
