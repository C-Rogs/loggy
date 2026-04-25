import Foundation

/// Timestamp-driven rest countdown derived from persisted `rest_timer_state.ends_at`.
enum RestTimerService {
    static func remainingSeconds(endsAt: Date?, now: Date = Date()) -> Int? {
        guard let endsAt else { return nil }
        return max(0, Int(endsAt.timeIntervalSince(now).rounded(.down)))
    }
}
