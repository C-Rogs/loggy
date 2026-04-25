import ActivityKit
import Foundation

final class LiveActivityManager: @unchecked Sendable {
    @MainActor
    private var activity: Activity<WorkoutActivityAttributes>?

    @MainActor
    func startIfNeeded(sessionId: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if activity != nil { return }

        let attributes = WorkoutActivityAttributes(workoutSessionId: sessionId)
        let state = WorkoutActivityAttributes.ContentState(
            elapsedSeconds: 0,
            completedSetCount: 0,
            currentExerciseName: "Workout",
            restRemainingSeconds: nil
        )

        do {
            activity = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
        } catch {
            activity = nil
        }
    }

    @MainActor
    func update(
        elapsedSeconds: Int,
        completedSetCount: Int,
        currentExerciseName: String,
        restRemainingSeconds: Int?
    ) async {
        guard let activity else { return }
        await activity.update(
            using: WorkoutActivityAttributes.ContentState(
                elapsedSeconds: elapsedSeconds,
                completedSetCount: completedSetCount,
                currentExerciseName: currentExerciseName,
                restRemainingSeconds: restRemainingSeconds
            )
        )
    }

    @MainActor
    func end() async {
        guard let activity else { return }
        await activity.end(dismissalPolicy: .immediate)
        self.activity = nil
    }
}
