import Foundation
import GRDB
import os.log

extension Logger {
    /// Visible in Console / `idevicesyslog` when filtering subsystem `com.loggy.app`.
    static let database = Logger(subsystem: "com.loggy.app", category: "database")
}

/// Holds the shared database pool and runs migrations.
public final class AppDatabase: @unchecked Sendable {
    public let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public static func openShared() throws -> AppDatabase {
        let url = try databaseURL()
        Logger.database.info("Opening database at \(url.path, privacy: .public)")
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA busy_timeout = 8000")
        }
        let pool: DatabasePool
        do {
            pool = try DatabasePool(path: url.path, configuration: config)
        } catch {
            Logger.database.error("DatabasePool init failed: \(String(describing: error), privacy: .public)")
            throw error
        }
        do {
            try AppMigrator().migrate(pool)
        } catch {
            Logger.database.error("Migration failed: \(LoggyDatabaseStartupDiagnostics.formattedMessage(for: error), privacy: .public)")
            throw error
        }
        Logger.database.info("Database open and migrations OK")
        return AppDatabase(pool: pool)
    }

    /// Deletes `Application Support/Loggy` (SQLite + WAL/SHM). **All local workouts and related data are removed.**
    public static func removeSharedDatabaseStoreForRecovery() throws {
        let fm = FileManager.default
        let dir = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("Loggy", isDirectory: true)
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
        }
    }

    private static func databaseURL() throws -> URL {
        try applicationSupportLoggyDirectory(createIfNeeded: true).appendingPathComponent("loggy.sqlite")
    }

    private static func applicationSupportLoggyDirectory(createIfNeeded: Bool) throws -> URL {
        let fm = FileManager.default
        let dir = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createIfNeeded
        ).appendingPathComponent("Loggy", isDirectory: true)
        if createIfNeeded, !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}

// MARK: - Startup diagnostics (SQLite codes are real; free space is only one possible cause)

enum LoggyDatabaseStartupDiagnostics {
    /// Full GRDB/SQLite detail for the error screen (and Console copy).
    static func formattedMessage(for error: Error) -> String {
        if let db = error as? DatabaseError {
            var lines: [String] = [db.description]
            lines.append("SQLite extended code: \(db.extendedResultCode.rawValue)")
            return lines.joined(separator: "\n")
        }
        return error.localizedDescription
    }
}
