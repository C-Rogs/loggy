import ActivityKit
import Foundation

/// Shared between the app and the Live Activity widget extension.
public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var elapsedSeconds: Int
        public var completedSetCount: Int
        public var currentExerciseName: String
        public var restRemainingSeconds: Int?
        /// Wall-clock end of active rest; lock screen uses this with `TimelineView` for a stable numeric countdown.
        public var restEndsAt: Date?
        /// Start of the current rest interval (for progress bar while the display updates locally).
        public var restStartedAt: Date?
        /// Elapsed fraction of the current rest interval (0…1) for lock-screen progress bar; nil when not resting.
        public var restProgress: Double?

        public var liveSessionExerciseId: String?
        public var liveSetEntryId: String?
        public var currentSetTitle: String
        public var nextSetPreview: String
        public var previousDisplayCompact: String
        public var currentKgDisplay: String
        public var currentRepsDisplay: String
        public var heartBpm: Int?
        public var activeKcalDisplay: String?

        public init(
            elapsedSeconds: Int,
            completedSetCount: Int,
            currentExerciseName: String,
            restRemainingSeconds: Int?,
            restEndsAt: Date? = nil,
            restStartedAt: Date? = nil,
            restProgress: Double? = nil,
            liveSessionExerciseId: String? = nil,
            liveSetEntryId: String? = nil,
            currentSetTitle: String = "",
            nextSetPreview: String = "",
            previousDisplayCompact: String = "—",
            currentKgDisplay: String = "—",
            currentRepsDisplay: String = "—",
            heartBpm: Int? = nil,
            activeKcalDisplay: String? = nil
        ) {
            self.elapsedSeconds = elapsedSeconds
            self.completedSetCount = completedSetCount
            self.currentExerciseName = currentExerciseName
            self.restRemainingSeconds = restRemainingSeconds
            self.restEndsAt = restEndsAt
            self.restStartedAt = restStartedAt
            self.restProgress = restProgress
            self.liveSessionExerciseId = liveSessionExerciseId
            self.liveSetEntryId = liveSetEntryId
            self.currentSetTitle = currentSetTitle
            self.nextSetPreview = nextSetPreview
            self.previousDisplayCompact = previousDisplayCompact
            self.currentKgDisplay = currentKgDisplay
            self.currentRepsDisplay = currentRepsDisplay
            self.heartBpm = heartBpm
            self.activeKcalDisplay = activeKcalDisplay
        }
    }

    public var workoutSessionId: String

    public init(workoutSessionId: String) {
        self.workoutSessionId = workoutSessionId
    }
}
