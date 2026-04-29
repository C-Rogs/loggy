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
                SELECT id, display_name, exercise_mode, is_custom, primary_muscle_group
                FROM exercise
                WHERE deleted_at IS NULL
                ORDER BY sort_name COLLATE NOCASE ASC
            """)
        }
    }

    public func searchExercises(query: String, primaryMuscleSlug: String?, exerciseMode: ExerciseMode?) throws -> [ExerciseSummary] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern: String? = q.isEmpty ? nil : "%\(q.lowercased())%"
        var sql = """
            SELECT DISTINCT e.id, e.display_name, e.exercise_mode, e.is_custom, e.primary_muscle_group
            FROM exercise e
            """
        var args: [any DatabaseValueConvertible] = []
        if pattern != nil {
            sql += " LEFT JOIN exercise_alias a ON a.exercise_id = e.id"
        }
        sql += " WHERE e.deleted_at IS NULL"
        if let pattern {
            sql += """
                 AND (
                    lower(e.display_name) LIKE ?
                    OR lower(e.canonical_name) LIKE ?
                    OR lower(a.alias) LIKE ?
                  )
                """
            args.append(contentsOf: [pattern, pattern, pattern])
        }
        if let slug = primaryMuscleSlug?.trimmingCharacters(in: .whitespacesAndNewlines), !slug.isEmpty {
            sql += " AND lower(trim(e.primary_muscle_group)) = lower(?)"
            args.append(slug)
        }
        if let mode = exerciseMode {
            sql += " AND e.exercise_mode = ?"
            args.append(mode.rawValue)
        }
        sql += " ORDER BY e.sort_name COLLATE NOCASE ASC"
        return try pool.read { db in
            try Self.fetchSummaries(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    public func replacementCandidates(forExerciseId: String, limit: Int = 40) throws -> [ExerciseSummary] {
        try pool.read { db in
            guard let anchor = try Row.fetchOne(
                db,
                sql: """
                    SELECT display_name, canonical_name, exercise_mode, primary_muscle_group, secondary_muscle_groups_json
                    FROM exercise
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [forExerciseId]
            ) else { return [] }

            let display: String = anchor["display_name"]
            let canonical: String = anchor["canonical_name"]
            let mode: String = anchor["exercise_mode"]
            let primary: String? = anchor["primary_muscle_group"]
            let anchorBucket = ExerciseMuscleBucket.bucket(
                primaryMuscle: primary,
                displayName: display,
                canonicalName: canonical
            )

            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, display_name, exercise_mode, is_custom, canonical_name, primary_muscle_group, secondary_muscle_groups_json
                    FROM exercise
                    WHERE deleted_at IS NULL AND id != ? AND exercise_mode = ?
                    ORDER BY sort_name COLLATE NOCASE ASC
                    """,
                arguments: [forExerciseId, mode]
            )

            var preferred: [ExerciseSummary] = []
            var other: [ExerciseSummary] = []
            for row in rows {
                let secJSON: String = (row["secondary_muscle_groups_json"] as String?) ?? "[]"
                let cb = ExerciseMuscleBucket.bucket(
                    primaryMuscle: row["primary_muscle_group"] as String?,
                    displayName: row["display_name"] as String,
                    canonicalName: row["canonical_name"] as String
                )
                let secHit = ExerciseMuscleBucket.secondaryJSONMatchesBucket(secJSON, bucket: anchorBucket)
                let summary = ExerciseSummary(
                    id: row["id"],
                    displayName: row["display_name"],
                    exerciseMode: ExerciseMode(rawValue: row["exercise_mode"] as String) ?? .weightReps,
                    isCustom: (row["is_custom"] as Int?) == 1,
                    primaryMuscleGroup: row["primary_muscle_group"]
                )
                if anchorBucket == .unknown {
                    other.append(summary)
                } else if cb == anchorBucket || secHit {
                    preferred.append(summary)
                } else {
                    other.append(summary)
                }
            }

            var combined: [ExerciseSummary] = []
            var seen = Set<String>()
            for s in preferred + other where seen.insert(s.id).inserted {
                combined.append(s)
                if combined.count >= limit { break }
            }
            return combined
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

    public func exerciseHowTo(exerciseId: String) throws -> ExerciseHowToInfo? {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, display_name, instruction_text, gif_url,
                           primary_muscle_group, secondary_muscle_groups_json
                    FROM exercise
                    WHERE id = ? AND deleted_at IS NULL
                """,
                arguments: [exerciseId]
            ) else { return nil }
            let secJSON: String = (row["secondary_muscle_groups_json"] as String?) ?? "[]"
            let secondary: [String] = (try? JSONDecoder().decode([String].self, from: Data(secJSON.utf8))) ?? []
            return ExerciseHowToInfo(
                id: row["id"],
                displayName: row["display_name"],
                instructionText: row["instruction_text"],
                gifURL: row["gif_url"],
                primaryMuscleGroup: row["primary_muscle_group"],
                secondaryMuscleGroups: secondary
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
                isCustom: (row["is_custom"] as Int?) == 1,
                primaryMuscleGroup: row["primary_muscle_group"]
            )
        }
    }
}
