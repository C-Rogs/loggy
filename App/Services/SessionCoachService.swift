import Foundation
import GRDB

/// Rules-first session naming before starting an empty workout (no exercise auto-fill in v1).
public final class SessionCoachService: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func suggestedSessionTitle(now: Date = Date()) throws -> String {
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

        let focus: String
        if legs && !push { focus = "Upper" }
        else if push && !pull { focus = "Pull" }
        else if pull && !push { focus = "Push" }
        else if push && pull { focus = "Legs" }
        else { focus = ["Push", "Pull", "Legs", "Upper"][cal.component(.weekday, from: now) % 4] }

        let dateBit = formatter.string(from: now)
        return "\(focus) — \(dateBit)"
    }
}
