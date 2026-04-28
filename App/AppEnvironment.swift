import Foundation
import GRDB
import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    let database: AppDatabase
    let workouts: WorkoutSessionRepository
    let exercises: ExerciseRepository
    let restTimers: RestTimerRepository
    let templates: TemplateRepository
    let importBatches: ImportBatchRepository
    let coach: CoachRepository
    let hevyImporter: HevyCSVImporter
    let coachService: CoachService
    let liveActivity: LiveActivityManager
    let nextExerciseSuggestion: NextExerciseSuggestionService
    let sessionCoach: SessionCoachService
    let csvExporter: LoggyCSVExporter
    let appleHealth: AppleHealthWorkoutService

    init() throws {
        let database = try AppDatabase.openShared()
        try SeedDatabase.seedIfNeeded(pool: database.pool)
        #if DEBUG
        try SampleHistorySeeder.seedIfNeeded(pool: database.pool)
        #endif
        self.database = database

        let pool = database.pool
        let workouts = WorkoutSessionRepository(pool: pool)
        self.workouts = workouts
        self.appleHealth = AppleHealthWorkoutService(workouts: workouts)
        self.exercises = ExerciseRepository(pool: pool)
        self.restTimers = RestTimerRepository(pool: pool)
        self.templates = TemplateRepository(pool: pool)
        self.importBatches = ImportBatchRepository(pool: pool)
        self.coach = CoachRepository(pool: pool)
        self.hevyImporter = HevyCSVImporter(pool: pool, importRepo: importBatches)
        self.coachService = CoachService(coach: coach)
        self.liveActivity = LiveActivityManager()
        self.nextExerciseSuggestion = NextExerciseSuggestionService(pool: pool)
        self.sessionCoach = SessionCoachService(pool: pool)
        self.csvExporter = LoggyCSVExporter(pool: pool)
    }

    /// Handles `loggy://workout/live-action?...` from Live Activity links (lock screen).
    func handleWorkoutLiveURL(_ url: URL) {
        guard let p = LoggyWorkoutDeepLink.parse(url) else { return }
        guard let active = try? workouts.activeSessionSummary(), active.sessionId == p.sessionId else { return }
        let sid = p.sessionId
        switch p.op {
        case .complete:
            guard let wse = p.wse, let setId = p.setId else { return }
            try? workouts.completeSet(sessionId: sid, sessionExerciseId: wse, setId: setId)
        case .weightDelta:
            guard let setId = p.setId, let d = p.delta else { return }
            guard let row = try? database.pool.read({ db in
                try Row.fetchOne(
                    db,
                    sql: """
                        SELECT weight_kg, reps, distance_km, duration_seconds, rpe
                        FROM set_entry WHERE id = ? AND deleted_at IS NULL
                        """,
                    arguments: [setId]
                )
            }) else { return }
            let w: Double? = row["weight_kg"]
            let nextW = max(0, (w ?? 0) + d)
            try? workouts.updateSet(
                setId: setId,
                weightKg: nextW,
                reps: row["reps"],
                distanceKm: row["distance_km"],
                durationSeconds: row["duration_seconds"],
                rpe: row["rpe"]
            )
        case .repsDelta:
            guard let setId = p.setId, let d = p.delta else { return }
            guard let row = try? database.pool.read({ db in
                try Row.fetchOne(
                    db,
                    sql: """
                        SELECT weight_kg, reps, distance_km, duration_seconds, rpe
                        FROM set_entry WHERE id = ? AND deleted_at IS NULL
                        """,
                    arguments: [setId]
                )
            }) else { return }
            let r: Int? = row["reps"]
            let nextR = max(0, (r ?? 0) + Int(d.rounded()))
            try? workouts.updateSet(
                setId: setId,
                weightKg: row["weight_kg"],
                reps: nextR,
                distanceKm: row["distance_km"],
                durationSeconds: row["duration_seconds"],
                rpe: row["rpe"]
            )
        case .skipRest:
            if let snap = try? restTimers.activeTimer(for: sid) {
                try? restTimers.skipTimer(timerId: snap.id)
            }
        }
        NotificationCenter.default.post(name: .loggyActiveWorkoutMutated, object: sid)
        Task { @MainActor in
            let state = ActiveWorkoutViewModel.liveActivitySnapshotAfterMutation(sessionId: sid, env: self)
            await liveActivity.update(sessionId: sid, state: state)
        }
    }
}
