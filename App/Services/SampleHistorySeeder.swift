import Foundation
import GRDB

/// Inserts several months of completed sample workouts once per install (DEBUG builds only).
enum SampleHistorySeeder {
    private static let defaultsKey = "LoggySampleHistorySeeded_v1"
    private static let calendar = Calendar(identifier: .gregorian)

    /// Deterministic “noise” from an index (no `random()` so builds are reproducible).
    private static func pseudoMix(_ i: Int) -> Int {
        var z = i &* 1_103_515_245 &+ 12_345_678
        z ^= z >> 16
        z &*= 2_654_435_761
        z ^= z >> 13
        return abs(z)
    }

    static func seedIfNeeded(pool: DatabasePool) throws {
        guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return }

        let exerciseIds: [String] = try pool.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM exercise WHERE deleted_at IS NULL
                    ORDER BY sort_name ASC
                    LIMIT 8
                    """
            )
        }
        guard exerciseIds.count >= 3 else { return }

        let anchor = calendar.startOfDay(for: Date())
        // ~18 weeks: every 2–3 days a session
        var sessionsInserted = 0
        try pool.write { db in
            var dayOffset = 0
            var idx = 0
            while dayOffset < 130 {
                guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: anchor) else { break }
                let mix = pseudoMix(idx)
                // ~3 sessions / week: skip some days
                if mix % 5 != 0 {
                    try insertCompletedSession(db: db, day: day, sessionIndex: idx, exerciseIds: exerciseIds, mix: mix)
                    sessionsInserted += 1
                }
                idx += 1
                dayOffset += 1 + (mix % 2) // advance 1 or 2 days
            }
        }
        guard sessionsInserted > 0 else { return }
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }

    private static func insertCompletedSession(
        db: Database,
        day: Date,
        sessionIndex: Int,
        exerciseIds: [String],
        mix: Int
    ) throws {
        let sid = UUID().uuidString
        let hour = 17 + (mix % 3)
        let minute = (mix / 7) % 50
        let started = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        let durationSec = 2_400 + (mix % 4_000)
        let ended = started.addingTimeInterval(TimeInterval(durationSec))
        let startedAt = ISO8601UTC.string(from: started)
        let endedAt = ISO8601UTC.string(from: ended)
        let now = startedAt
        let titles = ["Push", "Pull", "Legs", "Upper", "Full body", "Strength"]
        let title = titles[mix % titles.count]

        try db.execute(
            sql: """
                INSERT INTO workout_session (
                    id, title, notes, started_at, ended_at, status, source,
                    total_duration_seconds_cache, total_volume_kg_cache, total_set_count_cache, total_rep_count_cache,
                    created_at, updated_at
                ) VALUES (?, ?, NULL, ?, ?, 'completed', 'manual',
                    ?, 0, 0, 0, ?, ?)
                """,
            arguments: [sid, title, startedAt, endedAt, durationSec, now, now]
        )

        let a = exerciseIds[mix % exerciseIds.count]
        let b = exerciseIds[(mix / 3) % exerciseIds.count]
        let chosen: [String] = a != b ? [a, b] : [a, exerciseIds[(mix + 1) % exerciseIds.count]]

        for (order, eid) in chosen.enumerated() {
            let wseId = UUID().uuidString
            let mode: String = try String.fetchOne(
                db,
                sql: "SELECT exercise_mode FROM exercise WHERE id = ?",
                arguments: [eid]
            ) ?? ExerciseMode.weightReps.rawValue

            try db.execute(
                sql: """
                    INSERT INTO workout_session_exercise (
                        id, workout_session_id, exercise_id, block_id, display_order, notes,
                        exercise_mode, target_rest_seconds, is_collapsed, created_at, updated_at
                    ) VALUES (?, ?, ?, NULL, ?, NULL, ?, 90, 0, ?, ?)
                    """,
                arguments: [wseId, sid, eid, order, mode, now, now]
            )

            let setCount = 3 + (mix % 3)
            for s in 0 ..< setCount {
                let setId = UUID().uuidString
                let baseW = 40.0 + Double((mix + sessionIndex * 17 + s * 11) % 55)
                let reps = 5 + (mix + s) % 8
                let completed = ISO8601UTC.string(from: started.addingTimeInterval(TimeInterval(120 * (s + 1))))
                try db.execute(
                    sql: """
                        INSERT INTO set_entry (
                            id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                            weight_kg, reps, distance_km, duration_seconds, rpe,
                            completed_at, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, 'completed', ?, ?, NULL, NULL, NULL, ?, ?, ?)
                        """,
                    arguments: [setId, wseId, eid, s, SetType.normal.rawValue, baseW, reps, completed, now, now]
                )
            }
        }

        try WorkoutTotalsService().recomputeCaches(db: db, sessionId: sid)
    }
}
