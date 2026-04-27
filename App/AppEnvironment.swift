import Foundation
import SwiftUI

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

    init() throws {
        let database = try AppDatabase.openShared()
        try SeedDatabase.seedIfNeeded(pool: database.pool)
        self.database = database

        let pool = database.pool
        self.workouts = WorkoutSessionRepository(pool: pool)
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
}
