import Foundation
import GRDB

enum PreviousValueMatcher {
    /// Display-only "Previous" string derived from prior completed workouts (never persisted on the set row).
    static func previousDisplay(
        db: Database,
        exerciseId: String,
        excludingSessionId: String,
        setType: SetType,
        setIndex: Int,
        mode: ExerciseMode
    ) throws -> String {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT se.set_index, se.weight_kg, se.reps, se.distance_km, se.duration_seconds, se.set_type, se.completed_at
                FROM set_entry se
                JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                JOIN workout_session ws ON ws.id = wse.workout_session_id
                WHERE COALESCE(se.logged_exercise_id, wse.exercise_id) = ?
                  AND se.status = 'completed'
                  AND se.deleted_at IS NULL
                  AND wse.deleted_at IS NULL
                  AND ws.deleted_at IS NULL
                  AND ws.status = 'completed'
                  AND ws.id != ?
                ORDER BY se.completed_at DESC
                LIMIT 80
            """,
            arguments: [exerciseId, excludingSessionId]
        )

        let targetBucketWarmup = (setType == .warmup)

        func bucketMatches(_ candidateType: SetType) -> Bool {
            (candidateType == .warmup) == targetBucketWarmup
        }

        func readSetIndex(_ row: Row) -> Int {
            if let v: Int = row["set_index"] { return v }
            if let v: Int64 = row["set_index"] { return Int(v) }
            return -1
        }

        if let row = rows.first(where: { r in
            let t = SetType(rawValue: r["set_type"] as String) ?? .normal
            return bucketMatches(t) && readSetIndex(r) == setIndex
        }) ?? rows.first(where: { r in
            let t = SetType(rawValue: r["set_type"] as String) ?? .normal
            return bucketMatches(t)
        }) ?? rows.first {
            return formatPrevious(row: row, mode: mode)
        }

        return "—"
    }

    private static func formatPrevious(row: Row, mode: ExerciseMode) -> String {
        let w: Double? = row["weight_kg"]
        let r: Int? = row["reps"]
        let dkm: Double? = row["distance_km"]
        let ds: Int? = row["duration_seconds"]

        switch mode {
        case .weightReps, .bodyweightReps:
            if let w, let r {
                let ws = Self.trim(w)
                return "\(ws) × \(r)"
            }
            if let r { return "\(r) reps" }
            if let w { return "\(Self.trim(w)) kg" }
            return "—"
        case .duration:
            if let ds { return Self.formatDuration(ds) }
            return "—"
        case .distanceDuration:
            if let dkm, let ds {
                return "\(Self.trim(dkm)) km · \(Self.formatDuration(ds))"
            }
            if let dkm { return "\(Self.trim(dkm)) km" }
            if let ds { return Self.formatDuration(ds) }
            return "—"
        }
    }

    private static func trim(_ x: Double) -> String {
        if x.rounded() == x { return String(Int(x)) }
        return String(format: "%.1f", x)
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 { return String(format: "%d:%02d", m, s) }
        return "\(s)s"
    }
}
