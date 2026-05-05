import Foundation
import GRDB

/// Rules-first session naming before starting an empty workout (no exercise auto-fill in v1).
public final class SessionCoachService: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    /// Push / pull / legs rotation plus optional readiness + volume caps from rolling baselines.
    public func suggestedSessionTitle(now: Date = Date()) throws -> String {
        try suggestedSessionTitle(now: now, readinessBand: nil, baseline: nil)
    }

    public func suggestedSessionTitle(
        now: Date = Date(),
        readinessBand: ReadinessBand?,
        baseline: TrainingBaselineSnapshot?
    ) throws -> String {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        let lastTitles = try pool.read { db -> [String] in
            try String.fetchAll(
                db,
                sql: """
                    SELECT COALESCE(title, '') AS t
                    FROM workout_session
                    WHERE status = 'completed' AND deleted_at IS NULL
                    ORDER BY started_at DESC
                    LIMIT 8
                    """
            )
        }

        let lowered = lastTitles.map { $0.lowercased() }
        func mentions(_ needle: String) -> Bool { lowered.contains { $0.contains(needle) } }

        let push = mentions("push") || mentions("chest") || mentions("shoulder")
        let pull = mentions("pull") || mentions("back")
        let legs = mentions("leg") || mentions("lower")

        var focus: String
        if legs && !push { focus = "Upper" }
        else if push && !pull { focus = "Pull" }
        else if pull && !push { focus = "Push" }
        else if push && pull { focus = "Legs" }
        else { focus = ["Push", "Pull", "Legs", "Upper"][cal.component(.weekday, from: now) % 4] }

        // Readiness cap: bias toward lighter push when recovery is low (wording only — user edits title freely).
        if readinessBand == .low {
            if focus == "Push" || focus == "Legs" {
                focus = "Upper"
            }
        }

        let dateBit = formatter.string(from: now)
        var title = "\(focus) — \(dateBit)"

        if readinessBand == .low {
            title += " · easy"
        }

        // Volume advisory: last 7d materially above rolling 4-week weekly average → hint deload awareness.
        if let base = baseline,
           let expWeek = base.avgWeeklyVolumeKgLast28Days,
           expWeek > 100,
           base.sumVolumeKgLast7Days > expWeek * 1.35
        {
            title += " · deload?"
        }

        return title
    }
}
