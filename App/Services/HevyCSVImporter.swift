import CryptoKit
import Foundation
import GRDB

struct HevyImportResult: Sendable {
    let importedWorkouts: Int
    let skippedDuplicate: Bool
}

/// Imports Hevy workout export CSV into normalized tables (see `Docs/05_IMPORT_MAPPING.md`).
final class HevyCSVImporter: Sendable {
    private let pool: DatabasePool
    private let importRepo: ImportBatchRepositoryProtocol

    init(pool: DatabasePool, importRepo: ImportBatchRepositoryProtocol) {
        self.pool = pool
        self.importRepo = importRepo
    }

    /// - Parameter onProgress: Called from the importer’s execution context (often a background queue); hop to MainActor in the handler if updating UI.
    func importCSV(
        data: Data,
        filename: String?,
        onProgress: (@Sendable (Double, String) -> Void)? = nil
    ) throws -> HevyImportResult {
        onProgress?(0.02, "Checking file…")
        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        if try importRepo.hasImported(contentSHA256: hash) {
            onProgress?(1.0, "Already imported")
            return HevyImportResult(importedWorkouts: 0, skippedDuplicate: true)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw HevyImportError.invalidEncoding
        }

        onProgress?(0.06, "Parsing CSV…")
        let rows = CSVUtil.parseRows(text)
        guard !rows.isEmpty else {
            onProgress?(1.0, "Done")
            return HevyImportResult(importedWorkouts: 0, skippedDuplicate: false)
        }

        let header = rows[0].map { $0.lowercased() }
        guard let titleIdx = header.firstIndex(of: "title"),
              let startIdx = header.firstIndex(of: "start_time"),
              let endIdx = header.firstIndex(of: "end_time"),
              let descIdx = header.firstIndex(of: "description"),
              let exIdx = header.firstIndex(of: "exercise_title"),
              let supIdx = header.firstIndex(of: "superset_id"),
              let notesIdx = header.firstIndex(of: "exercise_notes"),
              let setIdx = header.firstIndex(of: "set_index"),
              let typeIdx = header.firstIndex(of: "set_type"),
              let wIdx = header.firstIndex(of: "weight_kg"),
              let rIdx = header.firstIndex(of: "reps"),
              let dkmIdx = header.firstIndex(of: "distance_km"),
              let durIdx = header.firstIndex(of: "duration_seconds"),
              let rpeIdx = header.firstIndex(of: "rpe")
        else {
            throw HevyImportError.missingHeader
        }

        let dataRows = rows.dropFirst().filter { row in
            !row.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        struct WorkoutKey: Hashable {
            let title: String
            let start: String
            let end: String
        }

        var groups: [WorkoutKey: [[String]]] = [:]
        for r in dataRows {
            guard r.count > max(titleIdx, startIdx, endIdx, exIdx) else { continue }
            let key = WorkoutKey(title: r[titleIdx], start: r[startIdx], end: r[endIdx])
            groups[key, default: []].append(r)
        }

        var imported = 0
        let now = ISO8601UTC.string(from: Date())

        let sortedKeys = groups.keys.sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            if a.title != b.title { return a.title < b.title }
            return a.end < b.end
        }

        let totalWorkouts = sortedKeys.count
        if totalWorkouts == 0 {
            onProgress?(1.0, "Done")
            try importRepo.recordImport(contentSHA256: hash, filename: filename)
            return HevyImportResult(importedWorkouts: 0, skippedDuplicate: false)
        }

        onProgress?(0.08, "Found \(totalWorkouts) workout\(totalWorkouts == 1 ? "" : "s")…")

        let progressSpan = 0.90 / Double(totalWorkouts)
        for (idx, key) in sortedKeys.enumerated() {
            onProgress?(0.08 + progressSpan * Double(idx), "Importing workout \(idx + 1) of \(totalWorkouts)…")
            guard let lines = groups[key], let first = lines.first else { continue }
            try pool.write { db in
                let title: String? = Self.nilIfEmpty(first[titleIdx])
                let notes: String? = Self.nilIfEmpty(first[descIdx])
                let startedAt = try Self.parseHevyDate(first[startIdx]).map(ISO8601UTC.string(from:)) ?? now
                let endedAt = try Self.parseHevyDate(first[endIdx]).map(ISO8601UTC.string(from:))

                let sessionId = UUID().uuidString
                try db.execute(
                    sql: """
                        INSERT INTO workout_session (
                            id, title, notes, started_at, ended_at, status, source,
                            total_volume_kg_cache, total_set_count_cache, total_rep_count_cache,
                            created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, 'completed', 'import', 0, 0, 0, ?, ?)
                    """,
                    arguments: [sessionId, title, notes, startedAt, endedAt, now, now]
                )

                var supersetMap: [String: String] = [:]
                var displayOrder = 0

                var i = 0
                while i < lines.count {
                    let line = lines[i]
                    let exerciseTitle = line[exIdx]
                    let supersetId: String? = Self.nilIfEmpty(line[supIdx])

                    // Contiguous rows for the same exercise occurrence
                    var j = i
                    while j < lines.count {
                        let l2 = lines[j]
                        if l2[exIdx] != exerciseTitle { break }
                        if (Self.nilIfEmpty(l2[supIdx]) ?? "") != (supersetId ?? "") { break }
                        j += 1
                    }

                    let exerciseId = try Self.resolveOrCreateExerciseId(db: db, title: exerciseTitle, now: now)

                    var blockId: String?
                    if let supersetId, !supersetId.isEmpty {
                        if let existing = supersetMap[supersetId] {
                            blockId = existing
                        } else {
                            let bid = UUID().uuidString
                            let blockOrder = supersetMap.count
                            try db.execute(
                                sql: """
                                    INSERT INTO workout_block (
                                        id, workout_session_id, block_type, display_order, external_superset_id, created_at, updated_at
                                    ) VALUES (?, ?, 'superset', ?, ?, ?, ?)
                                """,
                                arguments: [bid, sessionId, blockOrder, supersetId, now, now]
                            )
                            supersetMap[supersetId] = bid
                            blockId = bid
                        }
                    }

                    let wseId = UUID().uuidString
                    try db.execute(
                        sql: """
                            INSERT INTO workout_session_exercise (
                                id, workout_session_id, exercise_id, block_id, display_order, notes,
                                exercise_mode, target_rest_seconds, is_collapsed, created_at, updated_at
                            ) VALUES (?, ?, ?, ?, ?, ?, (SELECT exercise_mode FROM exercise WHERE id = ?), NULL, 0, ?, ?)
                        """,
                        arguments: [
                            wseId,
                            sessionId,
                            exerciseId,
                            blockId,
                            displayOrder,
                            Self.nilIfEmpty(line[notesIdx]),
                            exerciseId,
                            now,
                            now
                        ]
                    )
                    displayOrder += 1

                    for k in i ..< j {
                        let lk = lines[k]
                        let setIndex = Int(lk[setIdx]) ?? 0
                        let setType = Self.nilIfEmpty(lk[typeIdx]) ?? "normal"
                        let weight = Double(lk[wIdx])
                        let reps = Int(lk[rIdx])
                        let dkm = Double(lk[dkmIdx])
                        let dur = Int(lk[durIdx])
                        let rpe = Double(lk[rpeIdx])

                        let setId = UUID().uuidString
                        try db.execute(
                            sql: """
                                INSERT INTO set_entry (
                                    id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                                    weight_kg, reps, distance_km, duration_seconds, rpe,
                                    completed_at, created_at, updated_at
                                ) VALUES (?, ?, ?, ?, ?, 'completed', ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                            arguments: [
                                setId, wseId, exerciseId, setIndex, setType,
                                weight, reps, dkm, dur, rpe,
                                endedAt ?? startedAt, now, now
                            ]
                        )
                    }

                    i = j
                }

                try WorkoutTotalsService().recomputeCaches(db: db, sessionId: sessionId)
                try PRService().recomputeForSession(db: db, sessionId: sessionId)
                try ExerciseHistoryService().rebuildSnapshotsForSession(db: db, sessionId: sessionId)
            }

            imported += 1
            onProgress?(0.08 + progressSpan * Double(idx + 1), "Imported \(imported) of \(totalWorkouts)")
        }

        onProgress?(0.98, "Saving import record…")
        try importRepo.recordImport(contentSHA256: hash, filename: filename)
        onProgress?(1.0, "Done")
        return HevyImportResult(importedWorkouts: imported, skippedDuplicate: false)
    }

    private static func nilIfEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func parseHevyDate(_ s: String) throws -> Date? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "d MMM yyyy, HH:mm"
        if let d = df.date(from: t) { return d }

        df.dateFormat = "dd MMM yyyy, HH:mm"
        if let d = df.date(from: t) { return d }

        return ISO8601UTC.date(from: t)
    }

    private static func resolveOrCreateExerciseId(db: Database, title: String, now: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.lowercased()
        guard !key.isEmpty else {
            throw HevyImportError.invalidRow
        }

        if let id = try String.fetchOne(
            db,
            sql: """
                SELECT e.id FROM exercise e
                LEFT JOIN exercise_alias a ON a.exercise_id = e.id
                WHERE e.deleted_at IS NULL
                  AND (lower(e.display_name) = ? OR lower(e.canonical_name) = ? OR a.normalized_alias = ?)
                LIMIT 1
            """,
            arguments: [key, key, key]
        ) {
            return id
        }

        let id = UUID().uuidString
        let canonical = trimmed.lowercased()
        try db.execute(
            sql: """
                INSERT INTO exercise (
                    id, canonical_name, display_name, exercise_mode, equipment_type,
                    primary_muscle_group, secondary_muscle_groups_json, is_custom, sort_name,
                    created_at, updated_at
                ) VALUES (?, ?, ?, 'weight_reps', NULL, NULL, '[]', 1, ?, ?, ?)
            """,
            arguments: [id, canonical, trimmed, canonical, now, now]
        )
        try db.execute(
            sql: """
                INSERT INTO exercise_alias (id, exercise_id, alias, normalized_alias, created_at)
                VALUES (?, ?, ?, ?, ?)
            """,
            arguments: [UUID().uuidString, id, trimmed, canonical, now]
        )
        return id
    }
}

enum HevyImportError: Error {
    case invalidEncoding
    case missingHeader
    case invalidRow
}

extension HevyImportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "That file isn’t valid UTF-8 text. Export the CSV again from Hevy."
        case .missingHeader:
            return "This CSV doesn’t match Hevy’s export columns. Use Hevy’s backup export CSV."
        case .invalidRow:
            return "A row in the file couldn’t be imported. Try re-exporting from Hevy."
        }
    }
}

enum CSVUtil {
    static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var idx = 0
        while idx < chars.count {
            let ch = chars[idx]
            if inQuotes {
                if ch == "\"" {
                    if idx + 1 < chars.count, chars[idx + 1] == "\"" {
                        field.append("\"")
                        idx += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"":
                    inQuotes = true
                case ",":
                    current.append(field)
                    field = ""
                case "\n", "\r":
                    if ch == "\r", idx + 1 < chars.count, chars[idx + 1] == "\n" {
                        idx += 1
                    }
                    current.append(field)
                    field = ""
                    if !current.isEmpty {
                        rows.append(current)
                        current = []
                    }
                default:
                    field.append(ch)
                }
            }
            idx += 1
        }
        current.append(field)
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}
