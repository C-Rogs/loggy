import Foundation
import GRDB
import SwiftUI
import os.log

extension Logger {
    static let startup = Logger(subsystem: "com.loggy.app", category: "startup")
    static let lockScreenAction = Logger(subsystem: "com.loggy.app", category: "lockScreenAction")
}

@MainActor
final class AppEnvironment: ObservableObject {
    /// Set when the main UI successfully constructs an environment; used by `LiveActivityIntent` to avoid a second full DB open.
    private(set) static var sharedForProcess: AppEnvironment?

    static func registerSharedInstance(_ env: AppEnvironment) {
        sharedForProcess = env
    }

    static func clearSharedInstance() {
        sharedForProcess = nil
    }

    /// Used by `LiveActivityIntent`: prefer the instance from `LoggyApp`, otherwise bootstrap once (cold process).
    static func sharedOrCreateForLockScreenAction() -> AppEnvironment? {
        if let s = sharedForProcess { return s }
        guard let env = try? AppEnvironment() else {
            Logger.lockScreenAction.error("Failed to create AppEnvironment for lock-screen / intent action")
            return nil
        }
        registerSharedInstance(env)
        Logger.lockScreenAction.notice("Bootstrapped AppEnvironment for lock-screen action (no prior shared instance)")
        return env
    }

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
    let healthRecovery: HealthRecoveryService
    let phoneWatchBridge: PhoneWatchSessionBridge

    init() throws {
        let database = try AppDatabase.openShared()
        do {
            try SeedDatabase.seedIfNeeded(pool: database.pool)
        } catch {
            Logger.startup.error("SeedDatabase failed: \(String(describing: error), privacy: .public)")
            throw error
        }
        #if DEBUG
        try SampleHistorySeeder.seedIfNeeded(pool: database.pool)
        #endif
        self.database = database

        let pool = database.pool
        let workouts = WorkoutSessionRepository(pool: pool)
        let appleHealth = AppleHealthWorkoutService(workouts: workouts)
        let phoneWatchBridge = PhoneWatchSessionBridge()
        appleHealth.phoneWatchBridge = phoneWatchBridge
        phoneWatchBridge.onLiveHeartRateFromWatch = { [weak appleHealth] bpm, at in
            appleHealth?.applyLiveHeartRateFromWatch(bpm: bpm, measuredAt: at)
        }

        self.workouts = workouts
        self.appleHealth = appleHealth
        self.phoneWatchBridge = phoneWatchBridge
        self.healthRecovery = HealthRecoveryService()
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
        phoneWatchBridge.activate()

        Task { @MainActor in
            await liveActivity.reconcileWithDatabase(workouts: workouts)
        }
    }

    /// Handles `loggy://workout/live-action?...` from URLs (e.g. `onOpenURL`).
    func handleWorkoutLiveURL(_ url: URL) {
        guard let p = LoggyWorkoutDeepLink.parse(url) else { return }
        handleWorkoutLiveParsed(p)
    }

    /// Shared by URL open and `LiveActivityIntent` so lock-screen actions can run without launching the app UI.
    func handleWorkoutLiveParsed(_ p: LoggyWorkoutDeepLink.Parsed) {
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
