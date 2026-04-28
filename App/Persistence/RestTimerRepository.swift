import Foundation
import GRDB

public final class RestTimerRepository: RestTimerRepositoryProtocol {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func activeTimer(for sessionId: String) throws -> RestTimerSnapshot? {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, workout_session_exercise_id, state, ends_at, started_at
                    FROM rest_timer_state
                    WHERE workout_session_id = ?
                      AND state = 'running'
                    ORDER BY last_action_at DESC
                    LIMIT 1
                """,
                arguments: [sessionId]
            ) else { return nil }

            let endsAt: Date? = (row["ends_at"] as String?).flatMap(ISO8601UTC.date(from:))
            let startedAt: Date? = (row["started_at"] as String?).flatMap(ISO8601UTC.date(from:))
            return RestTimerSnapshot(
                id: row["id"],
                sessionExerciseId: row["workout_session_exercise_id"],
                state: RestTimerStateKind(rawValue: row["state"]) ?? .idle,
                endsAt: endsAt,
                startedAt: startedAt
            )
        }
    }

    public func skipTimer(timerId: String) throws {
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE rest_timer_state
                    SET state = 'skipped', updated_at = ?, last_action_at = ?
                    WHERE id = ?
                    """,
                arguments: [now, now, timerId]
            )
        }
    }

    public func completeExpiredRunningTimersIfNeeded(sessionId: String) throws {
        let rows = try pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, ends_at FROM rest_timer_state
                    WHERE workout_session_id = ? AND state = 'running' AND ends_at IS NOT NULL
                    """,
                arguments: [sessionId]
            )
        }
        let now = Date()
        let ids: [String] = rows.compactMap { r -> String? in
            let id: String = r["id"]
            guard let endsStr: String = r["ends_at"],
                  let ends = ISO8601UTC.date(from: endsStr),
                  ends <= now
            else { return nil }
            return id
        }
        guard !ids.isEmpty else { return }
        let nowStr = ISO8601UTC.string(from: now)
        try pool.write { db in
            for id in ids {
                try db.execute(
                    sql: """
                        UPDATE rest_timer_state
                        SET state = 'completed', updated_at = ?, last_action_at = ?
                        WHERE id = ? AND state = 'running'
                        """,
                    arguments: [nowStr, nowStr, id]
                )
                try db.execute(
                    sql: """
                        INSERT INTO rest_timer_event (id, rest_timer_state_id, event_type, timestamp, delta_seconds, source, note)
                        VALUES (?, ?, 'completed', ?, NULL, 'auto', NULL)
                        """,
                    arguments: [UUID().uuidString, id, nowStr]
                )
            }
        }
    }

    public func adjustRunningTimer(sessionId: String, deltaSeconds: Int) throws {
        guard deltaSeconds != 0 else { return }
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, ends_at, user_adjusted_seconds
                    FROM rest_timer_state
                    WHERE workout_session_id = ? AND state = 'running'
                    ORDER BY last_action_at DESC
                    LIMIT 1
                    """,
                arguments: [sessionId]
            ) else { return }

            let timerId: String = row["id"]
            let endsStr: String? = row["ends_at"]
            let priorAdjust: Int = row["user_adjusted_seconds"] ?? 0
            guard let endsStr, let endsAt = ISO8601UTC.date(from: endsStr) else { return }

            let proposed = endsAt.addingTimeInterval(TimeInterval(deltaSeconds))
            let floor = Date().addingTimeInterval(1)
            let newEnds = proposed > floor ? proposed : floor
            let newEndsStr = ISO8601UTC.string(from: newEnds)

            try db.execute(
                sql: """
                    UPDATE rest_timer_state
                    SET ends_at = ?, user_adjusted_seconds = ?, updated_at = ?, last_action_at = ?
                    WHERE id = ?
                    """,
                arguments: [newEndsStr, priorAdjust + deltaSeconds, now, now, timerId]
            )
            try db.execute(
                sql: """
                    INSERT INTO rest_timer_event (id, rest_timer_state_id, event_type, timestamp, delta_seconds, source, note)
                    VALUES (?, ?, 'adjusted', ?, ?, 'manual', NULL)
                    """,
                arguments: [UUID().uuidString, timerId, now, deltaSeconds]
            )
        }
    }
}
