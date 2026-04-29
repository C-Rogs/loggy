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
                                id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                                created_at, updated_at
                            ) VALUES (?, ?, ?, ?, ?, 'planned', ?, ?)
                        """,
                        arguments: [setId, wseId, exerciseId, idx, setType.rawValue, now, now]
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
                        SELECT id, set_index, set_type, status, weight_kg, reps, distance_km, duration_seconds, rpe, completed_at, logged_exercise_id
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
                    let prevExerciseId: String = (sr["logged_exercise_id"] as String?) ?? exerciseId
                    let prev = try PreviousValueMatcher.previousDisplay(
                        db: db,
                        exerciseId: prevExerciseId,
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
            func intCol(_ row: Row, _ key: String) -> Int? {
                if let v: Int = row[key] { return v }
                if let v: Int64 = row[key] { return Int(v) }
                return nil
            }

            let mode: String = try String.fetchOne(
                db,
                sql: "SELECT exercise_mode FROM exercise WHERE id = ?",
                arguments: [exerciseId]
            ) ?? ExerciseMode.weightReps.rawValue
            let modeEnum = ExerciseMode(rawValue: mode) ?? .weightReps

            let sessionSource: String = try String.fetchOne(
                db,
                sql: "SELECT source FROM workout_session WHERE id = ? AND deleted_at IS NULL",
                arguments: [sessionId]
            ) ?? WorkoutSessionSource.manual.rawValue

            let sessionTitle: String? = try String.fetchOne(
                db,
                sql: "SELECT title FROM workout_session WHERE id = ? AND deleted_at IS NULL",
                arguments: [sessionId]
            )

            let nextOrder: Int = (try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(display_order), -1) + 1 FROM workout_session_exercise WHERE workout_session_id = ? AND deleted_at IS NULL",
                arguments: [sessionId]
            )) ?? 0

            let wseId = UUID().uuidString

            struct SetSeed {
                let setType: String
                let weightKg: Double?
                let reps: Int?
                let distanceKm: Double?
                let durationSeconds: Int?
            }

            var seeds: [SetSeed] = []
            var targetRestSeconds = 90

            var templateRow: Row?
            if sessionSource == WorkoutSessionSource.template.rawValue {
                let trimmedTitle = sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !trimmedTitle.isEmpty {
                    templateRow = try Row.fetchOne(
                        db,
                        sql: """
                            SELECT wte.target_set_count, wte.target_weight_kg, wte.target_rep_min, wte.target_rep_max,
                                   wte.target_duration_seconds, wte.target_distance_km, wte.default_rest_seconds, wte.default_set_type
                            FROM workout_template_exercise wte
                            JOIN workout_template wt ON wt.id = wte.workout_template_id AND wt.deleted_at IS NULL
                            WHERE wte.exercise_id = ? AND wte.deleted_at IS NULL
                              AND trim(COALESCE(wt.name, '')) = trim(?)
                            LIMIT 1
                            """,
                        arguments: [exerciseId, trimmedTitle]
                    )
                }
            }

            if let tr = templateRow {
                let count = max(intCol(tr, "target_set_count") ?? 3, 1)
                if let dr = intCol(tr, "default_rest_seconds") {
                    targetRestSeconds = dr
                }
                let setTypeStr: String? = tr["default_set_type"]
                let setType = (setTypeStr.flatMap { SetType(rawValue: $0) } ?? .normal).rawValue
                let tw: Double? = tr["target_weight_kg"]
                let rMin = intCol(tr, "target_rep_min")
                let rMax = intCol(tr, "target_rep_max")
                let mergedReps: Int? = {
                    if let a = rMin, let b = rMax { return (a + b) / 2 }
                    return rMin ?? rMax
                }()
                let tplDur = intCol(tr, "target_duration_seconds")
                let tplDist: Double? = tr["target_distance_km"]

                for _ in 0 ..< count {
                    switch modeEnum {
                    case .weightReps:
                        seeds.append(SetSeed(setType: setType, weightKg: tw, reps: mergedReps, distanceKm: nil, durationSeconds: nil))
                    case .bodyweightReps:
                        seeds.append(SetSeed(setType: setType, weightKg: nil, reps: mergedReps, distanceKm: nil, durationSeconds: nil))
                    case .duration:
                        seeds.append(SetSeed(setType: setType, weightKg: nil, reps: nil, distanceKm: nil, durationSeconds: tplDur))
                    case .distanceDuration:
                        seeds.append(SetSeed(setType: setType, weightKg: nil, reps: nil, distanceKm: tplDist, durationSeconds: tplDur))
                    }
                }
            }

            if seeds.isEmpty {
                if let histWse: String = try String.fetchOne(
                    db,
                    sql: """
                        SELECT wse.id
                        FROM workout_session_exercise wse
                        JOIN workout_session ws ON ws.id = wse.workout_session_id
                        WHERE wse.exercise_id = ? AND wse.deleted_at IS NULL AND ws.deleted_at IS NULL
                          AND ws.status = 'completed' AND ws.id != ?
                        ORDER BY datetime(COALESCE(ws.ended_at, ws.started_at)) DESC, wse.display_order ASC, wse.created_at DESC
                        LIMIT 1
                        """,
                    arguments: [exerciseId, sessionId]
                ) {
                    if let restRow = try Row.fetchOne(
                        db,
                        sql: "SELECT target_rest_seconds FROM workout_session_exercise WHERE id = ?",
                        arguments: [histWse]
                    ), let r = intCol(restRow, "target_rest_seconds") {
                        targetRestSeconds = r
                    }
                    let hRows = try Row.fetchAll(
                        db,
                        sql: """
                            SELECT set_type, weight_kg, reps, distance_km, duration_seconds
                            FROM set_entry
                            WHERE workout_session_exercise_id = ? AND deleted_at IS NULL
                            ORDER BY set_index ASC
                            """,
                        arguments: [histWse]
                    )
                    for hr in hRows {
                        let st: String = hr["set_type"] as String? ?? SetType.normal.rawValue
                        seeds.append(
                            SetSeed(
                                setType: st,
                                weightKg: hr["weight_kg"],
                                reps: intCol(hr, "reps"),
                                distanceKm: hr["distance_km"],
                                durationSeconds: intCol(hr, "duration_seconds")
                            )
                        )
                    }
                }
            }

            if seeds.isEmpty {
                seeds.append(SetSeed(setType: SetType.normal.rawValue, weightKg: nil, reps: nil, distanceKm: nil, durationSeconds: nil))
            }

            try db.execute(
                sql: """
                    INSERT INTO workout_session_exercise (
                        id, workout_session_id, exercise_id, block_id, display_order, notes,
                        exercise_mode, target_rest_seconds, is_collapsed, created_at, updated_at
                    ) VALUES (?, ?, ?, NULL, ?, NULL, ?, ?, 0, ?, ?)
                    """,
                arguments: [wseId, sessionId, exerciseId, nextOrder, mode, targetRestSeconds, now, now]
            )

            for (idx, s) in seeds.enumerated() {
                let setId = UUID().uuidString
                try db.execute(
                    sql: """
                        INSERT INTO set_entry (
                            id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                            weight_kg, reps, distance_km, duration_seconds,
                            created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, 'planned', ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [setId, wseId, exerciseId, idx, s.setType, s.weightKg, s.reps, s.distanceKm, s.durationSeconds, now, now]
                )
            }
        }
    }

    /// Swaps the canonical exercise for an in-session slot while keeping the same `workout_session_exercise` row and set rows.
    /// Requires the new exercise to use the same `exercise_mode` as the slot so existing set payloads stay valid.
    public func replaceSessionExercise(sessionId: String, sessionExerciseId: String, newExerciseId: String) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            guard let wseRow = try Row.fetchOne(
                db,
                sql: """
                    SELECT exercise_mode FROM workout_session_exercise
                    WHERE id = ? AND workout_session_id = ? AND deleted_at IS NULL
                    """,
                arguments: [sessionExerciseId, sessionId]
            ) else { throw RepositoryError.notFound }

            let slotMode: String = wseRow["exercise_mode"]

            guard let newRow = try Row.fetchOne(
                db,
                sql: "SELECT exercise_mode FROM exercise WHERE id = ? AND deleted_at IS NULL",
                arguments: [newExerciseId]
            ) else { throw RepositoryError.notFound }

            let newMode: String = newRow["exercise_mode"]
            guard newMode == slotMode else { throw RepositoryError.invalidExerciseReplacement }

            try db.execute(
                sql: """
                    UPDATE workout_session_exercise
                    SET exercise_id = ?, updated_at = ?
                    WHERE id = ? AND workout_session_id = ? AND deleted_at IS NULL
                    """,
                arguments: [newExerciseId, now, sessionExerciseId, sessionId]
            )

            // Planned / skipped sets belong to the new exercise; clear stale payloads from the old lift.
            try db.execute(
                sql: """
                    UPDATE set_entry
                    SET logged_exercise_id = ?,
                        weight_kg = NULL,
                        reps = NULL,
                        distance_km = NULL,
                        duration_seconds = NULL,
                        rpe = NULL,
                        rir = NULL,
                        updated_at = ?
                    WHERE workout_session_exercise_id = ?
                      AND deleted_at IS NULL
                      AND status != 'completed'
                    """,
                arguments: [newExerciseId, now, sessionExerciseId]
            )
        }
        try WorkoutTotalsService().recomputeCaches(pool: pool, sessionId: sessionId)
        try PRService().recomputeForSession(pool: pool, sessionId: sessionId)
        try ExerciseHistoryService().rebuildSnapshotsForSession(pool: pool, sessionId: sessionId)
    }

    public func removeSessionExercise(sessionId: String, sessionExerciseId: String) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            guard try String.fetchOne(
                db,
                sql: """
                    SELECT id FROM workout_session_exercise
                    WHERE id = ? AND workout_session_id = ? AND deleted_at IS NULL
                    """,
                arguments: [sessionExerciseId, sessionId]
            ) != nil else { return }

            try db.execute(
                sql: """
                    UPDATE rest_timer_state
                    SET state = 'skipped', updated_at = ?, last_action_at = ?
                    WHERE workout_session_id = ? AND workout_session_exercise_id = ?
                      AND state IN ('running','paused')
                    """,
                arguments: [now, now, sessionId, sessionExerciseId]
            )

            try db.execute(
                sql: "UPDATE set_entry SET deleted_at = ? WHERE workout_session_exercise_id = ? AND deleted_at IS NULL",
                arguments: [now, sessionExerciseId]
            )
            try db.execute(
                sql: "UPDATE workout_session_exercise SET deleted_at = ? WHERE id = ?",
                arguments: [now, sessionExerciseId]
            )

            let remaining = try Row.fetchAll(
                db,
                sql: """
                    SELECT id FROM workout_session_exercise
                    WHERE workout_session_id = ? AND deleted_at IS NULL
                    ORDER BY display_order ASC, created_at ASC
                    """,
                arguments: [sessionId]
            )
            for (idx, r) in remaining.enumerated() {
                let id: String = r["id"]
                try db.execute(
                    sql: "UPDATE workout_session_exercise SET display_order = ?, updated_at = ? WHERE id = ?",
                    arguments: [idx, now, id]
                )
            }

            try ActiveWorkoutStateRepository.touch(db: db, sessionId: sessionId, now: now)
        }
        try WorkoutTotalsService().recomputeCaches(pool: pool, sessionId: sessionId)
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

            let slotExerciseId: String = try String.fetchOne(
                db,
                sql: "SELECT exercise_id FROM workout_session_exercise WHERE id = ? AND deleted_at IS NULL",
                arguments: [sessionExerciseId]
            ) ?? ""

            let setId = UUID().uuidString
            try db.execute(
                sql: """
                    INSERT INTO set_entry (
                        id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                        weight_kg, reps, distance_km, duration_seconds,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, 'planned', ?, ?, ?, ?, ?, ?)
                """,
                arguments: [setId, sessionExerciseId, slotExerciseId, nextIndex, setType, weight, reps, dist, dur, now, now]
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
                    WHERE id = ? AND deleted_at IS NULL
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
                    SET logged_exercise_id = COALESCE(
                            logged_exercise_id,
                            (SELECT exercise_id FROM workout_session_exercise WHERE id = ?)
                        ),
                        status = 'completed', completed_at = ?, updated_at = ?
                    WHERE id = ? AND workout_session_exercise_id = ?
                """,
                arguments: [sessionExerciseId, now, now, setId, sessionExerciseId]
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

    public func uncompleteSet(sessionId: String, sessionExerciseId: String, setId: String) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            let sessionStatus: String = try String.fetchOne(
                db,
                sql: "SELECT status FROM workout_session WHERE id = ? AND deleted_at IS NULL",
                arguments: [sessionId]
            ) ?? ""
            guard sessionStatus == WorkoutSessionStatus.active.rawValue else { return }

            try db.execute(
                sql: """
                    UPDATE set_entry
                    SET status = 'planned', completed_at = NULL, updated_at = ?
                    WHERE id = ? AND workout_session_exercise_id = ? AND deleted_at IS NULL
                    """,
                arguments: [now, setId, sessionExerciseId]
            )

            try db.execute(
                sql: """
                    UPDATE rest_timer_state
                    SET state = 'skipped', updated_at = ?, last_action_at = ?
                    WHERE workout_session_id = ? AND state IN ('running','paused')
                    """,
                arguments: [now, now, sessionId]
            )

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
                    WHERE se.id = ? AND se.deleted_at IS NULL
                """,
                arguments: [setId]
            ) else { return }
            let wseId: String = row["id"]
            let sessionId: String = row["workout_session_id"]

            // Free UNIQUE(workout_session_exercise_id, set_index) slot before reindexing remaining rows.
            let sentinelIndex = Self.softDeletedSetIndexSentinel(setId: setId)
            try db.execute(
                sql: "UPDATE set_entry SET deleted_at = ?, set_index = ?, updated_at = ? WHERE id = ?",
                arguments: [now, sentinelIndex, now, setId]
            )

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

            try WorkoutTotalsService().recomputeCaches(db: db, sessionId: sessionId)
        }
    }

    /// Negative `set_index` for soft-deleted rows avoids UNIQUE(wse_id, set_index) collisions when reindexing.
    private static func softDeletedSetIndexSentinel(setId: String) -> Int {
        var h = 5381
        for b in setId.utf8 {
            h = ((h << 5) &+ h) &+ Int(b)
        }
        return -1_000_000 - (abs(h) % 999_000_000)
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
                    WHERE COALESCE(se.logged_exercise_id, wse.exercise_id) = ?
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

    public func exerciseHistoryBuckets(exerciseId: String, range: ExerciseHistoryTimeRange) throws -> [ExerciseHistoryBucket] {
        let periodExpr: String = switch range {
        case .month: "strftime('%Y-W%W', f.completed_at)"
        case .year: "strftime('%Y-%m', f.completed_at)"
        case .allTime: "strftime('%Y', f.completed_at)"
        }
        let dateClause: String
        var arguments: [any DatabaseValueConvertible] = [exerciseId]
        if let darg = range.dateFilterArgument {
            dateClause = "AND date(se.completed_at) >= date('now', ?)"
            arguments.append(darg)
        } else {
            dateClause = ""
        }
        let sql = """
            WITH filtered AS (
                SELECT se.weight_kg, se.reps, se.completed_at, wse.workout_session_id AS sid
                FROM set_entry se
                INNER JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id AND wse.deleted_at IS NULL
                INNER JOIN workout_session ws ON ws.id = wse.workout_session_id AND ws.deleted_at IS NULL
                WHERE COALESCE(se.logged_exercise_id, wse.exercise_id) = ?
                  AND se.status = 'completed'
                  AND se.completed_at IS NOT NULL
                  AND se.deleted_at IS NULL
                  AND ws.status = 'completed'
                  \(dateClause)
            ),
            per_set AS (
                SELECT \(periodExpr) AS period_key,
                       f.completed_at,
                       f.weight_kg,
                       f.reps,
                       COALESCE(f.weight_kg, 0) * COALESCE(CAST(f.reps AS REAL), 0) AS set_vol,
                       f.sid
                FROM filtered f
            ),
            bucket_agg AS (
                SELECT period_key,
                       MIN(completed_at) AS sort_ts,
                       MAX(weight_kg) AS heaviest,
                       MAX(CASE WHEN weight_kg > 0 AND reps >= 1 AND reps < 37
                           THEN weight_kg * (36.0 / (37.0 - CAST(reps AS REAL))) END) AS e1rm,
                       MAX(set_vol) AS best_set_vol,
                       SUM(COALESCE(reps, 0)) AS total_reps
                FROM per_set
                GROUP BY period_key
            ),
            per_session_volume AS (
                SELECT period_key, sid, SUM(set_vol) AS session_total
                FROM per_set
                GROUP BY period_key, sid
            ),
            peak_session_volume AS (
                SELECT period_key, MAX(session_total) AS best_session_vol
                FROM per_session_volume
                GROUP BY period_key
            )
            SELECT bucket_agg.period_key,
                   strftime('%Y-%m-%d', bucket_agg.sort_ts) AS sort_date,
                   bucket_agg.heaviest,
                   bucket_agg.e1rm,
                   bucket_agg.best_set_vol,
                   bucket_agg.total_reps,
                   COALESCE(peak_session_volume.best_session_vol, 0) AS best_session_vol
            FROM bucket_agg
            LEFT JOIN peak_session_volume USING (period_key)
            ORDER BY bucket_agg.sort_ts ASC
            """
        return try pool.read { db in
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            return rows.map { row in
                ExerciseHistoryBucket(
                    periodKey: row["period_key"],
                    sortDate: row["sort_date"],
                    heaviestWeightKg: row["heaviest"],
                    estimatedOneRMKg: row["e1rm"],
                    bestSetVolumeKg: row["best_set_vol"] as Double? ?? 0,
                    bestSessionVolumeKg: row["best_session_vol"] as Double? ?? 0,
                    totalReps: (row["total_reps"] as Int64?).map(Int.init) ?? (row["total_reps"] as Int?) ?? 0
                )
            }
        }
    }

    public func completedSetCountsByPrimaryMuscle(sinceDaysAgo: Int?) throws -> [MuscleGroupSetCount] {
        if let s = sinceDaysAgo {
            return try completedSetCountsByPrimaryMuscle(fromDaysAgo: s, toDaysAgo: nil)
        }
        return try completedSetCountsByPrimaryMuscle(fromDaysAgo: nil, toDaysAgo: nil)
    }

    /// Inclusive lower bound `fromDaysAgo` (e.g. 30 = on/after "today minus 30 days") and optional exclusive upper `toDaysAgo` (e.g. 30 with from 60 = the 30-day block before the most recent 30 days).
    public func completedSetCountsByPrimaryMuscle(fromDaysAgo: Int?, toDaysAgo: Int?) throws -> [MuscleGroupSetCount] {
        var rangeParts: [String] = []
        if let f = fromDaysAgo {
            rangeParts.append("date(se.completed_at) >= date('now', '-\(f) days')")
        }
        if let t = toDaysAgo {
            rangeParts.append("date(se.completed_at) < date('now', '-\(t) days')")
        }
        let rangeClause = rangeParts.isEmpty ? "" : " AND " + rangeParts.joined(separator: " AND ")
        let sql = """
            SELECT e.primary_muscle_group AS slug,
                   COUNT(*) AS cnt
            FROM set_entry se
            INNER JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id AND wse.deleted_at IS NULL
            INNER JOIN workout_session ws ON ws.id = wse.workout_session_id AND ws.deleted_at IS NULL
            INNER JOIN exercise e ON e.id = COALESCE(se.logged_exercise_id, wse.exercise_id) AND e.deleted_at IS NULL
            WHERE se.status = 'completed'
              AND se.deleted_at IS NULL
              AND ws.status = 'completed'
              AND e.primary_muscle_group IS NOT NULL
              AND length(trim(e.primary_muscle_group)) > 0
              \(rangeClause)
            GROUP BY e.primary_muscle_group
            ORDER BY cnt DESC
            """
        return try pool.read { db in
            let rows = try Row.fetchAll(db, sql: sql, arguments: [])
            return Self.mapMuscleGroupCountRows(rows)
        }
    }

    public func exerciseSetFrequency(fromDaysAgo: Int?, toDaysAgo: Int?, limit: Int) throws -> [ExerciseSetFrequencyRow] {
        var rangeParts: [String] = []
        if let f = fromDaysAgo {
            rangeParts.append("date(se.completed_at) >= date('now', '-\(f) days')")
        }
        if let t = toDaysAgo {
            rangeParts.append("date(se.completed_at) < date('now', '-\(t) days')")
        }
        let rangeClause = rangeParts.isEmpty ? "" : " AND " + rangeParts.joined(separator: " AND ")
        let lim = max(1, min(limit, 500))
        let sql = """
            SELECT e.id AS eid,
                   e.display_name AS dname,
                   COUNT(*) AS cnt
            FROM set_entry se
            INNER JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id AND wse.deleted_at IS NULL
            INNER JOIN workout_session ws ON ws.id = wse.workout_session_id AND ws.deleted_at IS NULL
            INNER JOIN exercise e ON e.id = COALESCE(se.logged_exercise_id, wse.exercise_id) AND e.deleted_at IS NULL
            WHERE se.status = 'completed'
              AND se.deleted_at IS NULL
              AND ws.status = 'completed'
              \(rangeClause)
            GROUP BY e.id, e.display_name
            ORDER BY cnt DESC
            LIMIT \(lim)
            """
        return try pool.read { db in
            try Row.fetchAll(db, sql: sql, arguments: []).map { row in
                let cnt = (row["cnt"] as Int64?).map(Int.init) ?? (row["cnt"] as Int?) ?? 0
                return ExerciseSetFrequencyRow(
                    exerciseId: row["eid"],
                    displayName: row["dname"],
                    completedSetCount: cnt
                )
            }
        }
    }

    public func muscleDistributionCoarseCurrentVsPrevious(windowDays: Int) throws -> [MuscleCoarseDistributionRow] {
        let w = max(1, windowDays)
        let current = try completedSetCountsByPrimaryMuscle(fromDaysAgo: w, toDaysAgo: nil)
        let previous = try completedSetCountsByPrimaryMuscle(fromDaysAgo: w * 2, toDaysAgo: w)
        var curMap: [ExerciseMuscleBucket: Int] = [:]
        var prevMap: [ExerciseMuscleBucket: Int] = [:]
        for r in current {
            let slug = r.muscleSlug.lowercased()
            let bucket = ExerciseMuscleBucket.coarseBucketFromStoredSlug(slug) ?? .unknown
            curMap[bucket, default: 0] += r.completedSetCount
        }
        for r in previous {
            let slug = r.muscleSlug.lowercased()
            let bucket = ExerciseMuscleBucket.coarseBucketFromStoredSlug(slug) ?? .unknown
            prevMap[bucket, default: 0] += r.completedSetCount
        }
        return ExerciseMuscleBucket.distributionChartOrder.map { b in
            MuscleCoarseDistributionRow(
                bucketRaw: b.rawValue,
                title: b.distributionShortTitle,
                currentSetCount: curMap[b] ?? 0,
                previousSetCount: prevMap[b] ?? 0
            )
        }
    }

    public func weeklyMuscleSetRows(limitWeeks: Int) throws -> [WeeklyMuscleSetRow] {
        let weeks = max(1, min(limitWeeks, 104))
        let days = weeks * 7
        let sql = """
            SELECT strftime('%Y-W%W', se.completed_at) AS wk,
                   strftime('%Y-%m-%d', MIN(se.completed_at)) AS sort_lbl,
                   e.primary_muscle_group AS slug,
                   COUNT(*) AS cnt
            FROM set_entry se
            INNER JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id AND wse.deleted_at IS NULL
            INNER JOIN workout_session ws ON ws.id = wse.workout_session_id AND ws.deleted_at IS NULL
            INNER JOIN exercise e ON e.id = COALESCE(se.logged_exercise_id, wse.exercise_id) AND e.deleted_at IS NULL
            WHERE se.status = 'completed'
              AND se.deleted_at IS NULL
              AND ws.status = 'completed'
              AND e.primary_muscle_group IS NOT NULL
              AND length(trim(e.primary_muscle_group)) > 0
              AND date(se.completed_at) >= date('now', '-\(days) days')
            GROUP BY wk, slug
            ORDER BY MIN(se.completed_at) ASC, cnt DESC
            """
        return try pool.read { db in
            let rows = try Row.fetchAll(db, sql: sql, arguments: [])
            var byWeek: [String: (label: String, items: [MuscleGroupSetCount])] = [:]
            for row in rows {
                let wk: String = row["wk"]
                let lbl: String = row["sort_lbl"]
                guard let slug: String = row["slug"], !slug.isEmpty else { continue }
                let cnt = (row["cnt"] as Int64?).map(Int.init) ?? (row["cnt"] as Int?) ?? 0
                let item = MuscleGroupSetCount(
                    muscleSlug: slug,
                    displayLabel: MuscleDisplayName.forStoredSlug(slug),
                    completedSetCount: cnt
                )
                if byWeek[wk] == nil {
                    byWeek[wk] = (lbl, [item])
                } else {
                    var entry = byWeek[wk]!
                    entry.items.append(item)
                    byWeek[wk] = entry
                }
            }
            return byWeek.keys.sorted().map { key in
                let entry = byWeek[key]!
                return WeeklyMuscleSetRow(weekKey: key, sortDateLabel: entry.label, muscles: entry.items)
            }
        }
    }

    private static func mapMuscleGroupCountRows(_ rows: [Row]) -> [MuscleGroupSetCount] {
        rows.compactMap { row -> MuscleGroupSetCount? in
            guard let slug: String = row["slug"], !slug.isEmpty else { return nil }
            let cnt = (row["cnt"] as Int64?).map(Int.init) ?? (row["cnt"] as Int?) ?? 0
            return MuscleGroupSetCount(
                muscleSlug: slug,
                displayLabel: MuscleDisplayName.forStoredSlug(slug),
                completedSetCount: cnt
            )
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
    /// New exercise `exercise_mode` does not match the slot being replaced (set rows stay typed by mode).
    case invalidExerciseReplacement
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
