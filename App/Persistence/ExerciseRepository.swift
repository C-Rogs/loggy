import Foundation
import GRDB

public final class ExerciseRepository: ExerciseRepositoryProtocol {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func allExercises() throws -> [ExerciseSummary] {
        try pool.read { db in
            try Self.fetchSummaries(db, sql: """
                SELECT id, display_name, exercise_mode, is_custom
                FROM exercise
                WHERE deleted_at IS NULL
                ORDER BY sort_name COLLATE NOCASE ASC
            """)
        }
    }

    public func searchExercises(query: String) throws -> [ExerciseSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return try allExercises() }
        let pattern = "%\(q.lowercased())%"
        return try pool.read { db in
            try Self.fetchSummaries(db, sql: """
                SELECT DISTINCT e.id, e.display_name, e.exercise_mode, e.is_custom
                FROM exercise e
                LEFT JOIN exercise_alias a ON a.exercise_id = e.id
                WHERE e.deleted_at IS NULL
                  AND (
                    lower(e.display_name) LIKE ?
                    OR lower(e.canonical_name) LIKE ?
                    OR lower(a.alias) LIKE ?
                  )
                ORDER BY e.sort_name COLLATE NOCASE ASC
            """, arguments: [pattern, pattern, pattern])
        }
    }

    public func createCustomExercise(displayName: String, mode: ExerciseMode) throws -> String {
        let id = UUID().uuidString
        let now = ISO8601UTC.string(from: Date())
        let sort = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonical = sort.lowercased()
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO exercise (
                        id, canonical_name, display_name, exercise_mode, equipment_type,
                        primary_muscle_group, secondary_muscle_groups_json, is_custom, sort_name,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, ?, NULL, NULL, '[]', 1, ?, ?, ?)
                """,
                arguments: [id, canonical, sort, mode.rawValue, sort.lowercased(), now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO exercise_alias (id, exercise_id, alias, normalized_alias, created_at)
                    VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [UUID().uuidString, id, sort, sort.lowercased(), now]
            )
        }
        return id
    }

    public func addAlias(exerciseId: String, alias: String) throws {
        let now = ISO8601UTC.string(from: Date())
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let norm = trimmed.lowercased()
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO exercise_alias (id, exercise_id, alias, normalized_alias, created_at)
                    VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [UUID().uuidString, exerciseId, trimmed, norm, now]
            )
        }
    }

    public func resolveExerciseId(importedTitle: String) throws -> String? {
        let key = importedTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return try pool.read { db in
            try String.fetchOne(
                db,
                sql: """
                    SELECT e.id FROM exercise e
                    LEFT JOIN exercise_alias a ON a.exercise_id = e.id
                    WHERE e.deleted_at IS NULL
                      AND (lower(e.display_name) = ? OR lower(e.canonical_name) = ? OR a.normalized_alias = ?)
                    LIMIT 1
                """,
                arguments: [key, key, key]
            )
        }
    }

    private static func fetchSummaries(_ db: Database, sql: String, arguments: StatementArguments = .init()) throws -> [ExerciseSummary] {
        try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
            ExerciseSummary(
                id: row["id"],
                displayName: row["display_name"],
                exerciseMode: ExerciseMode(rawValue: row["exercise_mode"]) ?? .weightReps,
                isCustom: (row["is_custom"] as Int?) == 1
            )
        }
    }
}
