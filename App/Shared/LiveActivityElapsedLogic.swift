import Foundation

/// Pure helpers for Live Activity elapsed display and push coalescing (testable, shared with widget extension).
public enum LiveActivityElapsedLogic {
    /// Maximum elapsed shown on lock screen / island (prevents runaway display if dates are corrupt).
    public static let maxDisplayElapsedSeconds: Int = 48 * 3600

    /// Elapsed seconds for UI: anchored start when available, else fallback snapshot; clamps negative skew and caps absurd duration.
    public static func elapsedDisplaySeconds(now: Date, workoutStartedAt: Date?, fallbackElapsedSeconds: Int) -> Int {
        let fallback = max(0, min(fallbackElapsedSeconds, maxDisplayElapsedSeconds))
        guard let start = workoutStartedAt else { return fallback }
        let raw = Int(now.timeIntervalSince(start))
        if raw < 0 { return 0 }
        return min(raw, maxDisplayElapsedSeconds)
    }

    /// If start is far in the future (clock skew / bad row), omit anchor so widget uses fallback elapsed only.
    public static func sanitizedWorkoutStartedAt(_ startedAt: Date?, referenceNow: Date = Date()) -> Date? {
        guard let s = startedAt else { return nil }
        if s.timeIntervalSince(referenceNow) > 120 { return nil }
        return s
    }

    /// Bucket width for legacy-only rest (`restRemainingSeconds` without wall-clock `restEndsAt`).
    /// Smaller than wall-clock pushes would be (1/s) but avoids spamming ActivityKit when `startedAt` is missing.
    public static let legacyRestPushBucketSeconds: Int = 5

    /// Signature for deciding whether rest-related Live Activity fields changed enough to push.
    /// Wall-clock rest uses stable timer id + end; legacy integer remainder is bucketed to avoid per-second pushes.
    public static func restPushSignature(timerId: String?, restEndsAt: Date?, legacyRemainingSeconds: Int?) -> String {
        if let id = timerId, let end = restEndsAt {
            return "w|\(id)|\(end.timeIntervalSince1970)"
        }
        if let r = legacyRemainingSeconds {
            let bucket = r / max(1, legacyRestPushBucketSeconds)
            return "legacy|\(bucket)"
        }
        return "idle"
    }
}
