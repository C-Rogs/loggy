import ActivityKit
import Foundation

final class LiveActivityManager: @unchecked Sendable {
    @MainActor
    private var activity: Activity<WorkoutActivityAttributes>?

    /// Starts a Live Activity for `sessionId`, replacing any existing activity bound to a different session.
    @MainActor
    func startIfNeeded(sessionId: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let existing = activity {
            if !LiveActivitySessionBinding.shouldEndBeforeStarting(
                existingSessionId: existing.attributes.workoutSessionId,
                requestedSessionId: sessionId
            ) {
                return
            }
            await end()
        }

        let attributes = WorkoutActivityAttributes(workoutSessionId: sessionId)
        let state = WorkoutActivityAttributes.ContentState(
            elapsedSeconds: 0,
            completedSetCount: 0,
            currentExerciseName: "Workout",
            restRemainingSeconds: nil,
            restEndsAt: nil,
            restStartedAt: nil,
            restProgress: nil
        )

        do {
            let content = ActivityContent(state: state, staleDate: nil)
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            activity = nil
        }
    }

    @MainActor
    func update(sessionId: String, state: WorkoutActivityAttributes.ContentState) async {
        guard let activity else { return }
        guard LiveActivitySessionBinding.shouldAcceptUpdate(
            boundSessionId: activity.attributes.workoutSessionId,
            updateSessionId: sessionId
        ) else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        await activity.update(content)
    }

    @MainActor
    func end() async {
        guard let activity else { return }
        let final = WorkoutActivityAttributes.ContentState(
            elapsedSeconds: 0,
            completedSetCount: 0,
            currentExerciseName: "Workout",
            restRemainingSeconds: nil,
            restEndsAt: nil,
            restStartedAt: nil,
            restProgress: nil
        )
        let content = ActivityContent(state: final, staleDate: nil)
        await activity.end(content, dismissalPolicy: .immediate)
        self.activity = nil
    }
}
