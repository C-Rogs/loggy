import ActivityKit
import Foundation

/// Shared between the app and the Live Activity widget extension.
public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Snapshot of elapsed time when this payload was built (sets, HR, etc.). Lock screen prefers ``workoutStartedAt`` + `TimelineView` so it stays live without per-second pushes.
        public var elapsedSeconds: Int
        public var completedSetCount: Int
        public var currentExerciseName: String
        /// Wall-clock session start — widget derives live elapsed with `TimelineView` (same idea as Now Playing’s elapsed + playback rate: anchor time, local interpolation).
        public var workoutStartedAt: Date?
        public var restRemainingSeconds: Int?
        /// Wall-clock end of active rest; lock screen uses this with `TimelineView` for a stable numeric countdown.
        public var restEndsAt: Date?
        /// Start of the current rest interval (for progress bar while the display updates locally).
        public var restStartedAt: Date?
        /// Elapsed fraction of the current rest interval (0…1) for lock-screen progress bar; nil when not resting.
        public var restProgress: Double?
        /// After natural rest expiry, show a short “time to go” affordance in the Live Activity (widget compares to wall clock locally).
        public var restAttentionExpiresAt: Date?

        public var liveSessionExerciseId: String?
        public var liveSetEntryId: String?
        public var currentSetTitle: String
        public var nextSetPreview: String
        public var previousDisplayCompact: String
        public var currentKgDisplay: String
        public var currentRepsDisplay: String
        public var heartBpm: Int?
        public var activeKcalDisplay: String?
        /// Short hint when Health sync is on but BPM has not appeared yet (or read access is blocked). Keep glanceable.
        public var heartRateTip: String?

        public init(
            elapsedSeconds: Int,
            completedSetCount: Int,
            currentExerciseName: String,
            workoutStartedAt: Date? = nil,
            restRemainingSeconds: Int?,
            restEndsAt: Date? = nil,
            restStartedAt: Date? = nil,
            restProgress: Double? = nil,
            restAttentionExpiresAt: Date? = nil,
            liveSessionExerciseId: String? = nil,
            liveSetEntryId: String? = nil,
            currentSetTitle: String = "",
            nextSetPreview: String = "",
            previousDisplayCompact: String = "—",
            currentKgDisplay: String = "—",
            currentRepsDisplay: String = "—",
            heartBpm: Int? = nil,
            activeKcalDisplay: String? = nil,
            heartRateTip: String? = nil
        ) {
            self.elapsedSeconds = elapsedSeconds
            self.completedSetCount = completedSetCount
            self.currentExerciseName = currentExerciseName
            self.workoutStartedAt = workoutStartedAt
            self.restRemainingSeconds = restRemainingSeconds
            self.restEndsAt = restEndsAt
            self.restStartedAt = restStartedAt
            self.restProgress = restProgress
            self.restAttentionExpiresAt = restAttentionExpiresAt
            self.liveSessionExerciseId = liveSessionExerciseId
            self.liveSetEntryId = liveSetEntryId
            self.currentSetTitle = currentSetTitle
            self.nextSetPreview = nextSetPreview
            self.previousDisplayCompact = previousDisplayCompact
            self.currentKgDisplay = currentKgDisplay
            self.currentRepsDisplay = currentRepsDisplay
            self.heartBpm = heartBpm
            self.activeKcalDisplay = activeKcalDisplay
            self.heartRateTip = heartRateTip
        }
    }

    public var workoutSessionId: String

    public init(workoutSessionId: String) {
        self.workoutSessionId = workoutSessionId
    }
}
