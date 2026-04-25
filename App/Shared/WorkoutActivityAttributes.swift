import ActivityKit
import Foundation

/// Shared between the app and the Live Activity widget extension.
public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var elapsedSeconds: Int
        public var completedSetCount: Int
        public var currentExerciseName: String
        public var restRemainingSeconds: Int?

        public init(
            elapsedSeconds: Int,
            completedSetCount: Int,
            currentExerciseName: String,
            restRemainingSeconds: Int?
        ) {
            self.elapsedSeconds = elapsedSeconds
            self.completedSetCount = completedSetCount
            self.currentExerciseName = currentExerciseName
            self.restRemainingSeconds = restRemainingSeconds
        }
    }

    public var workoutSessionId: String

    public init(workoutSessionId: String) {
        self.workoutSessionId = workoutSessionId
    }
}
