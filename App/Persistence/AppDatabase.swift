import Foundation
import GRDB

/// Holds the shared database pool and runs migrations.
public final class AppDatabase: @unchecked Sendable {
    public let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public static func openShared() throws -> AppDatabase {
        let url = try databaseURL()
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: url.path, configuration: config)
        try AppMigrator().migrate(pool)
        return AppDatabase(pool: pool)
    }

    private static func databaseURL() throws -> URL {
        let fm = FileManager.default
        let dir = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Loggy", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("loggy.sqlite")
    }
}
