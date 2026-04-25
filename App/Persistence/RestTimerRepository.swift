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
}
