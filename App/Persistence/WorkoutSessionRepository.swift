import Foundation
import GRDB

public final class WorkoutSessionRepository: WorkoutSessionRepositoryProtocol {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func listCompletedSessions(limit: Int) throws -> [WorkoutListItem] {
        try pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, title, started_at, ended_at, status,
                           total_volume_kg_cache, total_set_count_cache
                    FROM workout_session
                    WHERE status = 'completed' AND deleted_at IS NULL
                    ORDER BY started_at DESC
                    LIMIT ?
                """,
                arguments: [limit]
            ).compactMap(Self.mapListItem)
        }
    }

    public func activeSessionSummary() throws -> ActiveWorkoutSummary? {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT ws.id, ws.title, ws.started_at, aws.recovery_state, aws.last_opened_at
                    FROM workout_session ws
                    JOIN active_workout_state aws ON aws.workout_session_id = ws.id
                    WHERE ws.status = 'active' AND ws.deleted_at IS NULL
                    LIMIT 1
                """
            ) else { return nil }
            return ActiveWorkoutSummary(
                sessionId: row["id"],
                title: row["title"],
                startedAt: ISO8601UTC.date(from: row["started_at"]) ?? Date(),
                recoveryState: RecoveryState(rawValue: row["recovery_state"]) ?? .active,
                lastOpenedAt: ISO8601UTC.date(from: row["last_opened_at"]) ?? Date()
            )
        }
    }

    public func createEmptyActiveSession(title: String?) throws -> String {
        let id = UUID().uuidString
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO workout_session (
                        id, title, notes, started_at, ended_at, status, source,
                        total_volume_kg_cache, total_set_count_cache, total_rep_count_cache,
                        created_at, updated_at
                    ) VALUES (?, ?, NULL, ?, NULL, 'active', 'manual', 0, 0, 0, ?, ?)
                """,
                arguments: [id, title, now, now, now]
            )
            try insertActiveState(db: db, sessionId: id, now: now)
        }
        return id
    }

    public func startSessionFromTemplate(templateId: String, title: String?) throws -> String {
        let sessionId = UUID().uuidString
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            let templateName: String? = try String.fetchOne(
                db,
                sql: "SELECT name FROM workout_template WHERE id = ? AND deleted_at IS NULL",
                arguments: [templateId]
            )
            let sessionTitle = title ?? templateName
            try db.execute(
                sql: """
                    INSERT INTO workout_session (
                        id, title, notes, started_at, ended_at, status, source,
                        total_volume_kg_cache, total_set_count_cache, total_rep_count_cache,
                        created_at, updated_at
                    ) VALUES (?, ?, NULL, ?, NULL, 'active', 'template', 0, 0, 0, ?, ?)
                """,
                arguments: [sessionId, sessionTitle, now, now, now]
            )
            try insertActiveState(db: db, sessionId: sessionId, now: now)

            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT exercise_id, display_order, notes, default_rest_seconds, target_set_count, default_set_type
                    FROM workout_template_exercise
                    WHERE workout_template_id = ? AND deleted_at IS NULL
                    ORDER BY display_order ASC
                """,
                arguments: [templateId]
            )

            for r in rows {
                let exerciseId: String = r["exercise_id"]
                let order: Int = r["display_order"]
                let notes: String? = r["notes"]
                let rest: Int? = r["default_rest_seconds"]
                let targetSets: Int? = r["target_set_count"]
                let defaultSetType: String? = r["default_set_type"]
                let mode: String = try String.fetchOne(
                    db,
                    sql: "SELECT exercise_mode FROM exercise WHERE id = ?",
                    arguments: [exerciseId]
                ) ?? ExerciseMode.weightReps.rawValue

                let wseId = UUID().uuidString
                try db.execute(
                    sql: """
                        INSERT INTO workout_session_exercise (
                            id, workout_session_id, exercise_id, block_id, display_order, notes,
                            exercise_mode, target_rest_seconds, is_collapsed, created_at, updated_at
                        ) VALUES (?, ?, ?, NULL, ?, ?, ?, ?, 0, ?, ?)
                    """,
                    arguments: [wseId, sessionId, exerciseId, order, notes, mode, rest, now, now]
                )

                let count = max(targetSets ?? 3, 1)
                let setType = SetType(rawValue: defaultSetType ?? "") ?? .normal
                for idx in 0 ..< count {
                    let setId = UUID().uuidString
                    try db.execute(
                        sql: """
                            INSERT INTO set_entry (
                                id, workout_session_exercise_id, set_index, set_type, status,
                                created_at, updated_at
                            ) VALUES (?, ?, ?, ?, 'planned', ?, ?)
                        """,
                        arguments: [setId, wseId, idx, setType.rawValue, now, now]
                    )
                }
            }
        }
        return sessionId
    }

    public func sessionExercises(sessionId: String) throws -> [SessionExerciseCard] {
        try pool.read { db in
            let exRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT wse.id, wse.exercise_id, e.display_name, wse.exercise_mode, wse.notes, wse.target_rest_seconds
                    FROM workout_session_exercise wse
                    JOIN exercise e ON e.id = wse.exercise_id
                    WHERE wse.workout_session_id = ? AND wse.deleted_at IS NULL
                    ORDER BY wse.display_order ASC
                """,
                arguments: [sessionId]
            )

            return try exRows.map { er in
                let wseId: String = er["id"]
                let exerciseId: String = er["exercise_id"]
                let name: String = er["display_name"]
                let mode = ExerciseMode(rawValue: er["exercise_mode"]) ?? .weightReps
                let notes: String? = er["notes"]
                let rest: Int? = er["target_rest_seconds"]

                let setRows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, set_index, set_type, status, weight_kg, reps, distance_km, duration_seconds, rpe, completed_at
                        FROM set_entry
                        WHERE workout_session_exercise_id = ? AND deleted_at IS NULL
                        ORDER BY set_index ASC
                    """,
                    arguments: [wseId]
                )

                let sets: [SetRowModel] = try setRows.map { sr in
                    let setType = SetType(rawValue: sr["set_type"]) ?? .normal
                    let status = SetStatus(rawValue: sr["status"]) ?? .planned
                    let completedAt: Date? = (sr["completed_at"] as String?).flatMap(ISO8601UTC.date(from:))
                    let prev = try PreviousValueMatcher.previousDisplay(
                        db: db,
                        exerciseId: exerciseId,
                        excludingSessionId: sessionId,
                        setType: setType,
                        setIndex: sr["set_index"],
                        mode: mode
                    )
                    return SetRowModel(
                        id: sr["id"],
                        setIndex: sr["set_index"],
                        setType: setType,
                        status: status,
                        weightKg: sr["weight_kg"],
                        reps: sr["reps"],
                        distanceKm: sr["distance_km"],
                        durationSeconds: sr["duration_seconds"],
                        rpe: sr["rpe"],
                        completedAt: completedAt,
                        previousDisplay: prev
                    )
                }

                return SessionExerciseCard(
                    id: wseId,
                    exerciseId: exerciseId,
                    displayName: name,
                    exerciseMode: mode,
                    notes: notes,
                    targetRestSeconds: rest,
                    sets: sets
                )
            }
        }
    }

    public func addExercise(sessionId: String, exerciseId: String) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            let mode: String = try String.fetchOne(
                db,
                sql: "SELECT exercise_mode FROM exercise WHERE id = ?",
                arguments: [exerciseId]
            ) ?? ExerciseMode.weightReps.rawValue

            let nextOrder: Int = (try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(display_order), -1) + 1 FROM workout_session_exercise WHERE workout_session_id = ? AND deleted_at IS NULL",
                arguments: [sessionId]
            )) ?? 0

            let wseId = UUID().uuidString
            try db.execute(
                sql: """
                    INSERT INTO workout_session_exercise (
                        id, workout_session_id, exercise_id, block_id, display_order, notes,
                        exercise_mode, target_rest_seconds, is_collapsed, created_at, updated_at
                    ) VALUES (?, ?, ?, NULL, ?, NULL, ?, 90, 0, ?, ?)
                """,
                arguments: [wseId, sessionId, exerciseId, nextOrder, mode, now, now]
            )

            // Start with one planned set
            let setId = UUID().uuidString
            try db.execute(
                sql: """
                    INSERT INTO set_entry (
                        id, workout_session_exercise_id, set_index, set_type, status,
                        created_at, updated_at
                    ) VALUES (?, ?, 0, 'normal', 'planned', ?, ?)
                """,
                arguments: [setId, wseId, now, now]
            )
        }
    }

    public func reorderExercises(sessionId: String, orderedExerciseRowIds: [String]) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            for (idx, id) in orderedExerciseRowIds.enumerated() {
                try db.execute(
                    sql: """
                        UPDATE workout_session_exercise
                        SET display_order = ?, updated_at = ?
                        WHERE id = ? AND workout_session_id = ?
                    """,
                    arguments: [idx, now, id, sessionId]
                )
            }
        }
    }

    public func addSet(sessionExerciseId: String, cloneFromSetId: String?) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            let nextIndex: Int = (try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(set_index), -1) + 1 FROM set_entry WHERE workout_session_exercise_id = ? AND deleted_at IS NULL",
                arguments: [sessionExerciseId]
            )) ?? 0

            var setType = SetType.normal.rawValue
            var weight: Double?
            var reps: Int?
            var dist: Double?
            var dur: Int?

            if let cloneFromSetId {
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT set_type, weight_kg, reps, distance_km, duration_seconds
                        FROM set_entry WHERE id = ?
                    """,
                    arguments: [cloneFromSetId]
                )
                setType = (row?["set_type"] as String?) ?? setType
                weight = row?["weight_kg"]
                reps = row?["reps"]
                dist = row?["distance_km"]
                dur = row?["duration_seconds"]
            }

            let setId = UUID().uuidString
            try db.execute(
                sql: """
                    INSERT INTO set_entry (
                        id, workout_session_exercise_id, set_index, set_type, status,
                        weight_kg, reps, distance_km, duration_seconds,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, ?, 'planned', ?, ?, ?, ?, ?, ?)
                """,
                arguments: [setId, sessionExerciseId, nextIndex, setType, weight, reps, dist, dur, now, now]
            )
        }
    }

    public func updateSet(
        setId: String,
        weightKg: Double?,
        reps: Int?,
        distanceKm: Double?,
        durationSeconds: Int?,
        rpe: Double?
    ) throws {
        let now = ISO8601UTC.string(from: Date())
        let sessionId: String? = try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE set_entry
                    SET weight_kg = ?, reps = ?, distance_km = ?, duration_seconds = ?, rpe = ?, updated_at = ?
                    WHERE id = ?
                """,
                arguments: [weightKg, reps, distanceKm, durationSeconds, rpe, now, setId]
            )
            return try String.fetchOne(
                db,
                sql: """
                    SELECT wse.workout_session_id
                    FROM set_entry se
                    JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                    WHERE se.id = ?
                """,
                arguments: [setId]
            )
        }
        if let sessionId {
            try WorkoutTotalsService().recomputeCaches(pool: pool, sessionId: sessionId)
            try PRService().recomputeForSession(pool: pool, sessionId: sessionId)
            try ExerciseHistoryService().rebuildSnapshotsForSession(pool: pool, sessionId: sessionId)
        }
    }

    public func updateSetType(setId: String, setType: SetType) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            try db.execute(
                sql: "UPDATE set_entry SET set_type = ?, updated_at = ? WHERE id = ?",
                arguments: [setType.rawValue, now, setId]
            )
        }
    }

    public func completeSet(sessionId: String, sessionExerciseId: String, setId: String) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            let before = try Row.fetchOne(
                db,
                sql: "SELECT status FROM set_entry WHERE id = ?",
                arguments: [setId]
            )
            let wasCompleted = (before?["status"] as String?) == SetStatus.completed.rawValue
            let sessionStatus: String = try String.fetchOne(
                db,
                sql: "SELECT status FROM workout_session WHERE id = ?",
                arguments: [sessionId]
            ) ?? "completed"
            let isLiveSession = (sessionStatus == WorkoutSessionStatus.active.rawValue)

            try db.execute(
                sql: """
                    UPDATE set_entry
                    SET status = 'completed', completed_at = ?, updated_at = ?
                    WHERE id = ? AND workout_session_exercise_id = ?
                """,
                arguments: [now, now, setId, sessionExerciseId]
            )

            if !wasCompleted, isLiveSession {
                // Replace running rest timers for this session (Hevy rule: new completion replaces timer)
                try db.execute(
                    sql: """
                        UPDATE rest_timer_state
                        SET state = 'skipped', updated_at = ?, last_action_at = ?
                        WHERE workout_session_id = ? AND state IN ('running','paused')
                    """,
                    arguments: [now, now, sessionId]
                )

                let restSeconds: Int = try Int.fetchOne(
                    db,
                    sql: "SELECT COALESCE(target_rest_seconds, 90) FROM workout_session_exercise WHERE id = ?",
                    arguments: [sessionExerciseId]
                ) ?? 90

                let started = Date()
                let ends = started.addingTimeInterval(TimeInterval(restSeconds))
                let timerId = UUID().uuidString
                let startedAt = ISO8601UTC.string(from: started)
                let endsAt = ISO8601UTC.string(from: ends)

                try db.execute(
                    sql: """
                        INSERT INTO rest_timer_state (
                            id, workout_session_id, workout_session_exercise_id, source_set_entry_id,
                            state, started_at, paused_at, ends_at, remaining_at_pause_seconds,
                            default_duration_seconds, user_adjusted_seconds, auto_started, last_action_at, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, 'running', ?, NULL, ?, NULL, ?, 0, 1, ?, ?, ?)
                    """,
                    arguments: [
                        timerId, sessionId, sessionExerciseId, setId,
                        startedAt, endsAt,
                        restSeconds,
                        now, now, now
                    ]
                )

                try db.execute(
                    sql: """
                        INSERT INTO rest_timer_event (id, rest_timer_state_id, event_type, timestamp, delta_seconds, source, note)
                        VALUES (?, ?, 'started', ?, NULL, 'auto', NULL)
                    """,
                    arguments: [UUID().uuidString, timerId, startedAt]
                )
            }

            try ActiveWorkoutStateRepository.touch(db: db, sessionId: sessionId, now: now)
        }

        try WorkoutTotalsService().recomputeCaches(pool: pool, sessionId: sessionId)
    }

    public func deleteSet(setId: String) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT wse.id, wse.workout_session_id
                    FROM set_entry se
                    JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                    WHERE se.id = ?
                """,
                arguments: [setId]
            ) else { return }
            let wseId: String = row["id"]
            let sessionId: String = row["workout_session_id"]

            try db.execute(sql: "UPDATE set_entry SET deleted_at = ? WHERE id = ?", arguments: [now, setId])

            let remaining = try Row.fetchAll(
                db,
                sql: "SELECT id FROM set_entry WHERE workout_session_exercise_id = ? AND deleted_at IS NULL ORDER BY set_index ASC",
                arguments: [wseId]
            )
            for (idx, r) in remaining.enumerated() {
                let id: String = r["id"]
                try db.execute(
                    sql: "UPDATE set_entry SET set_index = ?, updated_at = ? WHERE id = ?",
                    arguments: [idx, now, id]
                )
            }

            try WorkoutTotalsService().recomputeCaches(pool: pool, sessionId: sessionId)
        }
    }

    public func updateSessionExerciseNotes(sessionExerciseId: String, notes: String?) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            try db.execute(
                sql: "UPDATE workout_session_exercise SET notes = ?, updated_at = ? WHERE id = ?",
                arguments: [notes, now, sessionExerciseId]
            )
        }
    }

    public func updateTargetRest(sessionExerciseId: String, seconds: Int?) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            try db.execute(
                sql: "UPDATE workout_session_exercise SET target_rest_seconds = ?, updated_at = ? WHERE id = ?",
                arguments: [seconds, now, sessionExerciseId]
            )
        }
    }

    public func updateSessionTitle(sessionId: String, title: String?) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            try db.execute(
                sql: "UPDATE workout_session SET title = ?, updated_at = ? WHERE id = ?",
                arguments: [title, now, sessionId]
            )
        }
    }

    public func finishSession(sessionId: String) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE workout_session
                    SET status = 'completed', ended_at = ?, updated_at = ?
                    WHERE id = ?
                """,
                arguments: [now, now, sessionId]
            )
            try db.execute(
                sql: """
                    UPDATE rest_timer_state
                    SET state = 'skipped', updated_at = ?, last_action_at = ?
                    WHERE workout_session_id = ? AND state IN ('running','paused')
                """,
                arguments: [now, now, sessionId]
            )
            try db.execute(sql: "DELETE FROM active_workout_state WHERE workout_session_id = ?", arguments: [sessionId])
        }
        try WorkoutTotalsService().recomputeCaches(pool: pool, sessionId: sessionId)
        try PRService().recomputeForSession(pool: pool, sessionId: sessionId)
        try ExerciseHistoryService().rebuildSnapshotsForSession(pool: pool, sessionId: sessionId)
    }

    public func sessionHealthKitTiming(sessionId: String) throws -> (startedAt: Date, endedAt: Date?) {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT started_at, ended_at FROM workout_session WHERE id = ? AND deleted_at IS NULL",
                arguments: [sessionId]
            ) else {
                throw RepositoryError.notFound
            }
            let startedStr: String = row["started_at"]
            let endedStr: String? = row["ended_at"]
            let started = ISO8601UTC.date(from: startedStr) ?? Date()
            let ended = endedStr.flatMap { ISO8601UTC.date(from: $0) }
            return (started, ended)
        }
    }

    public func discardSession(sessionId: String) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE workout_session
                    SET status = 'discarded', ended_at = ?, updated_at = ?
                    WHERE id = ?
                """,
                arguments: [now, now, sessionId]
            )
            try db.execute(
                sql: """
                    UPDATE rest_timer_state
                    SET state = 'skipped', updated_at = ?, last_action_at = ?
                    WHERE workout_session_id = ? AND state IN ('running','paused')
                """,
                arguments: [now, now, sessionId]
            )
            try db.execute(sql: "DELETE FROM active_workout_state WHERE workout_session_id = ?", arguments: [sessionId])
        }
    }

    public func markRecoveryStale(sessionId: String) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            try db.execute(
                sql: "UPDATE active_workout_state SET recovery_state = 'stale', updated_at = ? WHERE workout_session_id = ?",
                arguments: [now, sessionId]
            )
        }
    }

    public func touchActiveState(sessionId: String) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            try ActiveWorkoutStateRepository.touch(db: db, sessionId: sessionId, now: now)
        }
    }

    public func loadSessionForEdit(sessionId: String) throws -> (status: WorkoutSessionStatus, title: String?) {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT status, title FROM workout_session WHERE id = ? AND deleted_at IS NULL",
                arguments: [sessionId]
            ) else {
                throw RepositoryError.notFound
            }
            let status = WorkoutSessionStatus(rawValue: row["status"]) ?? .completed
            let title: String? = row["title"]
            return (status, title)
        }
    }

    public func syncActiveWorkoutFocus(sessionId: String, sessionExerciseId: String?, setEntryId: String?) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE active_workout_state
                    SET current_workout_session_exercise_id = ?,
                        current_set_entry_id = ?,
                        updated_at = ?
                    WHERE workout_session_id = ?
                """,
                arguments: [sessionExerciseId, setEntryId, now, sessionId]
            )
        }
    }

    public func weeklyCompletedVolumeByWeek(limitWeeks: Int) throws -> [WeeklyVolumePoint] {
        let days = max(7, limitWeeks * 7)
        return try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT strftime('%Y-W%W', started_at) AS wk,
                           SUM(total_volume_kg_cache) AS vol
                    FROM workout_session
                    WHERE status = 'completed' AND deleted_at IS NULL
                      AND date(started_at) >= date('now', ?)
                    GROUP BY wk
                    ORDER BY wk ASC
                """,
                arguments: ["-\(days) days"]
            )
            return rows.map { row in
                WeeklyVolumePoint(weekKey: row["wk"], totalKg: row["vol"] as Double? ?? 0)
            }
        }
    }

    public func weeklyStatsForExercise(exerciseId: String, limitWeeks: Int) throws -> [ExerciseWeeklyStatPoint] {
        let days = max(7, limitWeeks * 7)
        return try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT strftime('%Y-W%W', se.completed_at) AS wk,
                           SUM(COALESCE(se.weight_kg, 0) * COALESCE(CAST(se.reps AS REAL), 0)) AS vol,
                           MAX(se.weight_kg) AS mx
                    FROM set_entry se
                    JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                    JOIN workout_session ws ON ws.id = wse.workout_session_id
                    WHERE wse.exercise_id = ?
                      AND se.status = 'completed'
                      AND se.completed_at IS NOT NULL
                      AND se.deleted_at IS NULL AND wse.deleted_at IS NULL AND ws.deleted_at IS NULL
                      AND ws.status = 'completed'
                      AND date(se.completed_at) >= date('now', ?)
                    GROUP BY wk
                    ORDER BY wk ASC
                """,
                arguments: [exerciseId, "-\(days) days"]
            )
            return rows.map { row in
                ExerciseWeeklyStatPoint(
                    weekKey: row["wk"],
                    volumeKg: row["vol"] as Double? ?? 0,
                    maxWeightKg: row["mx"] as Double?
                )
            }
        }
    }

    private static func mapListItem(_ row: Row) -> WorkoutListItem? {
        guard let started = ISO8601UTC.date(from: row["started_at"]) else { return nil }
        let ended: Date? = (row["ended_at"] as String?).flatMap(ISO8601UTC.date(from:))
        return WorkoutListItem(
            id: row["id"],
            title: row["title"],
            startedAt: started,
            endedAt: ended,
            status: WorkoutSessionStatus(rawValue: row["status"]) ?? .completed,
            totalVolumeKg: row["total_volume_kg_cache"],
            totalSetCount: row["total_set_count_cache"]
        )
    }

    private func insertActiveState(db: Database, sessionId: String, now: String) throws {
        try db.execute(
            sql: """
                INSERT INTO active_workout_state (
                    workout_session_id, current_workout_session_exercise_id, current_set_entry_id,
                    focused_field, paused_at, autosave_revision, recovery_state, last_opened_at, updated_at
                ) VALUES (?, NULL, NULL, NULL, NULL, 0, 'active', ?, ?)
            """,
            arguments: [sessionId, now, now]
        )
    }
}

enum RepositoryError: Error {
    case notFound
}

enum ActiveWorkoutStateRepository {
    static func touch(db: Database, sessionId: String, now: String) throws {
        try db.execute(
            sql: """
                UPDATE active_workout_state
                SET last_opened_at = ?, updated_at = ?, recovery_state = 'active'
                WHERE workout_session_id = ?
            """,
            arguments: [now, now, sessionId]
        )
    }
}
