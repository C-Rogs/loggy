import ActivityKit
import Foundation

/// Shared between the app and the Live Activity widget extension.
public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var elapsedSeconds: Int
        public var completedSetCount: Int
        public var currentExerciseName: String
        public var restRemainingSeconds: Int?
        /// Wall-clock end of active rest; lets the Dynamic Island use `Text(..., style: .timer)` without per-second pushes.
        public var restEndsAt: Date?

        public init(
            elapsedSeconds: Int,
            completedSetCount: Int,
            currentExerciseName: String,
            restRemainingSeconds: Int?,
            restEndsAt: Date? = nil
        ) {
            self.elapsedSeconds = elapsedSeconds
            self.completedSetCount = completedSetCount
            self.currentExerciseName = currentExerciseName
            self.restRemainingSeconds = restRemainingSeconds
            self.restEndsAt = restEndsAt
        }
    }

    public var workoutSessionId: String

    public init(workoutSessionId: String) {
        self.workoutSessionId = workoutSessionId
    }
}
