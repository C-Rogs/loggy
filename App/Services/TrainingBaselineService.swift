import Foundation
import GRDB

/// Rolling workout aggregates computed on read from SQLite (single-user scale — cheap enough without extra tables).
public struct TrainingBaselineSnapshot: Sendable, Equatable {
    /// Sum of `workout_session.total_volume_kg_cache` for completed sessions in the last 7 days.
    public var sumVolumeKgLast7Days: Double
    /// `SUM(volume last 28d) / 4` as a rolling “expected week” benchmark.
    public var avgWeeklyVolumeKgLast28Days: Double?
    public var completedSessionsLast7Days: Int
    /// Mean logged HR effort (HRR fraction) on sets that have `hr_effort_pct`, last 28 days.
    public var meanHrEffortFractionLast28Days: Double?

    public init(
        sumVolumeKgLast7Days: Double,
        avgWeeklyVolumeKgLast28Days: Double?,
        completedSessionsLast7Days: Int,
        meanHrEffortFractionLast28Days: Double?
    ) {
        self.sumVolumeKgLast7Days = sumVolumeKgLast7Days
        self.avgWeeklyVolumeKgLast28Days = avgWeeklyVolumeKgLast28Days
        self.completedSessionsLast7Days = completedSessionsLast7Days
        self.meanHrEffortFractionLast28Days = meanHrEffortFractionLast28Days
    }
}

public final class TrainingBaselineService: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func fetchSnapshot(at date: Date = Date()) throws -> TrainingBaselineSnapshot {
        let cal = Calendar.current
        guard let start7 = cal.date(byAdding: .day, value: -7, to: date),
              let start28 = cal.date(byAdding: .day, value: -28, to: date)
        else {
            return TrainingBaselineSnapshot(
                sumVolumeKgLast7Days: 0,
                avgWeeklyVolumeKgLast28Days: nil,
                completedSessionsLast7Days: 0,
                meanHrEffortFractionLast28Days: nil
            )
        }
        let iso7 = ISO8601UTC.string(from: start7)
        let iso28 = ISO8601UTC.string(from: start28)

        return try pool.read { db in
            let sum7 =
                try Double.fetchOne(
                    db,
                    sql: """
                        SELECT COALESCE(SUM(total_volume_kg_cache), 0)
                        FROM workout_session
                        WHERE status = 'completed' AND deleted_at IS NULL AND started_at >= ?
                        """,
                    arguments: [iso7]
                ) ?? 0

            let sessions7 =
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*)
                        FROM workout_session
                        WHERE status = 'completed' AND deleted_at IS NULL AND started_at >= ?
                        """,
                    arguments: [iso7]
                ) ?? 0

            let sum28 =
                try Double.fetchOne(
                    db,
                    sql: """
                        SELECT COALESCE(SUM(total_volume_kg_cache), 0)
                        FROM workout_session
                        WHERE status = 'completed' AND deleted_at IS NULL AND started_at >= ?
                        """,
                    arguments: [iso28]
                ) ?? 0

            let avgWeekly28 = sum28 > 0 ? sum28 / 4.0 : nil

            let meanHr =
                try Double.fetchOne(
                    db,
                    sql: """
                        SELECT AVG(se.hr_effort_pct)
                        FROM set_entry se
                        INNER JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                        INNER JOIN workout_session ws ON ws.id = wse.workout_session_id
                        WHERE ws.status = 'completed' AND ws.deleted_at IS NULL
                          AND se.status = 'completed' AND se.deleted_at IS NULL
                          AND se.hr_effort_pct IS NOT NULL
                          AND ws.started_at >= ?
                        """,
                    arguments: [iso28]
                )

            return TrainingBaselineSnapshot(
                sumVolumeKgLast7Days: sum7,
                avgWeeklyVolumeKgLast28Days: avgWeekly28,
                completedSessionsLast7Days: sessions7,
                meanHrEffortFractionLast28Days: meanHr
            )
        }
    }
}
