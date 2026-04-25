import Foundation
import GRDB

public final class ImportBatchRepository: ImportBatchRepositoryProtocol {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func hasImported(contentSHA256: String) throws -> Bool {
        try pool.read { db in
            let c: Int = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM import_batch WHERE content_sha256 = ?",
                arguments: [contentSHA256]
            ) ?? 0
            return c > 0
        }
    }

    public func recordImport(contentSHA256: String, filename: String?) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO import_batch (id, content_sha256, created_at, source_filename)
                    VALUES (?, ?, ?, ?)
                """,
                arguments: [UUID().uuidString, contentSHA256, now, filename]
            )
        }
    }
}
