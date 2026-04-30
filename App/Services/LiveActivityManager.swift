import ActivityKit
import Foundation

final class LiveActivityManager: @unchecked Sendable {
    @MainActor
    private var activity: Activity<WorkoutActivityAttributes>?

    /// Ends Live Activities that don’t match persisted workout state (e.g. after force-quit). Keeps the Dynamic Island in sync with the database.
    @MainActor
    func reconcileWithDatabase(workouts: WorkoutSessionRepository) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let allowedSessionId = try? workouts.activeSessionSummary()?.sessionId
        let all = Activity<WorkoutActivityAttributes>.activities

        if let allowedSessionId {
            var claimed = false
            for la in all where la.attributes.workoutSessionId == allowedSessionId {
                if !claimed {
                    activity = la
                    claimed = true
                } else {
                    await endActivity(la)
                }
            }
            for la in all where la.attributes.workoutSessionId != allowedSessionId {
                await endActivity(la)
            }
            if !claimed {
                activity = nil
            }
        } else {
            for la in all {
                await endActivity(la)
            }
            activity = nil
        }
    }

    /// Starts a Live Activity for `sessionId`, replacing any existing activity bound to a different session.
    @MainActor
    func startIfNeeded(sessionId: String, workoutStartedAt: Date?) async {
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
            workoutStartedAt: workoutStartedAt,
            restRemainingSeconds: nil,
            restEndsAt: nil,
            restStartedAt: nil,
            restProgress: nil,
            restAttentionExpiresAt: nil
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
        await endActivity(activity)
        self.activity = nil
    }

    @MainActor
    private func endActivity(_ activity: Activity<WorkoutActivityAttributes>) async {
        let final = WorkoutActivityAttributes.ContentState(
            elapsedSeconds: 0,
            completedSetCount: 0,
            currentExerciseName: "Workout",
            workoutStartedAt: nil,
            restRemainingSeconds: nil,
            restEndsAt: nil,
            restStartedAt: nil,
            restProgress: nil,
            restAttentionExpiresAt: nil
        )
        let content = ActivityContent(state: final, staleDate: nil)
        await activity.end(content, dismissalPolicy: .immediate)
        if self.activity?.id == activity.id {
            self.activity = nil
        }
    }
}
