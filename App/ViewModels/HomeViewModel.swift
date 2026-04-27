import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var completed: [WorkoutListItem] = []
    @Published private(set) var activeSummary: ActiveWorkoutSummary?
    @Published private(set) var weeklyVolume: [WeeklyVolumePoint] = []
    @Published var showRecovery: Bool = false

    func refresh(env: AppEnvironment) throws {
        completed = try env.workouts.listCompletedSessions(limit: 100)
        activeSummary = try env.workouts.activeSessionSummary()
        weeklyVolume = try env.workouts.weeklyCompletedVolumeByWeek(limitWeeks: 17)

        if let a = activeSummary {
            let idleSeconds = Date().timeIntervalSince(a.lastOpenedAt)
            if idleSeconds > 4 * 3600 {
                try env.workouts.markRecoveryStale(sessionId: a.sessionId)
                activeSummary = try env.workouts.activeSessionSummary()
            }
        }

        showRecovery = (activeSummary?.recoveryState == .stale)
    }
}
