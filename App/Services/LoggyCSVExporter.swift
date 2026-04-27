import Foundation
import GRDB
import SwiftUI
import UniformTypeIdentifiers

/// Minimal CSV export of completed workouts and sets (Loggy interchange format, not Hevy-shaped).
public final class LoggyCSVExporter: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func exportCompletedWorkoutsCSV() throws -> Data {
        let text = try pool.read { db -> String in
            var lines: [String] = [
                "workout_id,workout_title,started_at,ended_at,session_exercise_id,exercise_display_name,set_index,set_type,status,weight_kg,reps,distance_km,duration_seconds,completed_at"
            ]
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        ws.id AS wid,
                        ws.title AS wtitle,
                        ws.started_at AS wstart,
                        ws.ended_at AS wend,
                        wse.id AS wseid,
                        e.display_name AS ename,
                        CAST(se.set_index AS TEXT) AS sidx,
                        se.set_type AS stype,
                        se.status AS sstat,
                        se.weight_kg AS wkg,
                        CAST(se.reps AS TEXT) AS reps,
                        se.distance_km AS dkm,
                        CAST(se.duration_seconds AS TEXT) AS dur,
                        se.completed_at AS cat
                    FROM workout_session ws
                    JOIN workout_session_exercise wse ON wse.workout_session_id = ws.id AND wse.deleted_at IS NULL
                    JOIN exercise e ON e.id = wse.exercise_id
                    JOIN set_entry se ON se.workout_session_exercise_id = wse.id AND se.deleted_at IS NULL
                    WHERE ws.status = 'completed' AND ws.deleted_at IS NULL
                    ORDER BY ws.started_at ASC, wse.display_order ASC, se.set_index ASC
                """
            )
            for r in rows {
                let fields: [String] = [
                    Self.csvEscape(r["wid"] as String),
                    Self.csvEscape((r["wtitle"] as String?) ?? ""),
                    Self.csvEscape(r["wstart"] as String),
                    Self.csvEscape((r["wend"] as String?) ?? ""),
                    Self.csvEscape(r["wseid"] as String),
                    Self.csvEscape(r["ename"] as String),
                    Self.csvEscape((r["sidx"] as String?) ?? ""),
                    Self.csvEscape(r["stype"] as String),
                    Self.csvEscape(r["sstat"] as String),
                    Self.csvNumber(r["wkg"] as Double?),
                    Self.csvEscape((r["reps"] as String?) ?? ""),
                    Self.csvNumber(r["dkm"] as Double?),
                    Self.csvEscape((r["dur"] as String?) ?? ""),
                    Self.csvEscape((r["cat"] as String?) ?? "")
                ]
                lines.append(fields.joined(separator: ","))
            }
            return lines.joined(separator: "\n")
        }
        guard let data = text.data(using: String.Encoding.utf8) else {
            throw ExportError.encodingFailed
        }
        return data
    }

    private static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            let doubled = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(doubled)\""
        }
        return s
    }

    private static func csvNumber(_ d: Double?) -> String {
        guard let d else { return "" }
        return String(d)
    }

    private static func csvNumberInt(_ i: Int64?) -> String {
        guard let i else { return "" }
        return String(i)
    }

}

public enum ExportError: Error {
    case encodingFailed
}

/// Minimal `FileDocument` for SwiftUI `.fileExporter`.
public struct CSVExportDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
