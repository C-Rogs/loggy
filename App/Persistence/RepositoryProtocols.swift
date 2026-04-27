import Foundation
import GRDB

public protocol ExerciseRepositoryProtocol: Sendable {
    func allExercises() throws -> [ExerciseSummary]
    func searchExercises(query: String) throws -> [ExerciseSummary]
    func createCustomExercise(displayName: String, mode: ExerciseMode) throws -> String
    func addAlias(exerciseId: String, alias: String) throws
    func resolveExerciseId(importedTitle: String) throws -> String?
    func exerciseHowTo(exerciseId: String) throws -> ExerciseHowToInfo?
}

public protocol WorkoutSessionRepositoryProtocol: Sendable {
    func listCompletedSessions(limit: Int) throws -> [WorkoutListItem]
    func activeSessionSummary() throws -> ActiveWorkoutSummary?
    func createEmptyActiveSession(title: String?) throws -> String
    func startSessionFromTemplate(templateId: String, title: String?) throws -> String
    func sessionExercises(sessionId: String) throws -> [SessionExerciseCard]
    func addExercise(sessionId: String, exerciseId: String) throws
    func reorderExercises(sessionId: String, orderedExerciseRowIds: [String]) throws
    func addSet(sessionExerciseId: String, cloneFromSetId: String?) throws
    func updateSet(
        setId: String,
        weightKg: Double?,
        reps: Int?,
        distanceKm: Double?,
        durationSeconds: Int?,
        rpe: Double?
    ) throws
    func updateSetType(setId: String, setType: SetType) throws
    func completeSet(sessionId: String, sessionExerciseId: String, setId: String) throws
    func deleteSet(setId: String) throws
    func updateSessionExerciseNotes(sessionExerciseId: String, notes: String?) throws
    func updateTargetRest(sessionExerciseId: String, seconds: Int?) throws
    func updateSessionTitle(sessionId: String, title: String?) throws
    func finishSession(sessionId: String) throws
    func discardSession(sessionId: String) throws
    /// ISO timestamps for syncing a completed session to HealthKit.
    func sessionHealthKitTiming(sessionId: String) throws -> (startedAt: Date, endedAt: Date?)
    func markRecoveryStale(sessionId: String) throws
    func touchActiveState(sessionId: String) throws
    func loadSessionForEdit(sessionId: String) throws -> (status: WorkoutSessionStatus, title: String?)
    func syncActiveWorkoutFocus(sessionId: String, sessionExerciseId: String?, setEntryId: String?) throws
    func weeklyCompletedVolumeByWeek(limitWeeks: Int) throws -> [WeeklyVolumePoint]
    func weeklyStatsForExercise(exerciseId: String, limitWeeks: Int) throws -> [ExerciseWeeklyStatPoint]
}

public protocol RestTimerRepositoryProtocol: Sendable {
    func activeTimer(for sessionId: String) throws -> RestTimerSnapshot?
    func skipTimer(timerId: String) throws
}

public struct RestTimerSnapshot: Hashable, Sendable {
    public var id: String
    public var sessionExerciseId: String?
    public var state: RestTimerStateKind
    public var endsAt: Date?
    public var startedAt: Date?
}

public protocol TemplateRepositoryProtocol: Sendable {
    func listTemplates() throws -> [WorkoutTemplateSummary]
    func createTemplate(name: String) throws -> String
    func deleteTemplate(id: String) throws
    func addExerciseToTemplate(templateId: String, exerciseId: String) throws
    func listTemplateExercises(templateId: String) throws -> [ExerciseSummary]
}

public protocol ImportBatchRepositoryProtocol: Sendable {
    func hasImported(contentSHA256: String) throws -> Bool
    func recordImport(contentSHA256: String, filename: String?) throws
}

public protocol CoachRepositoryProtocol: Sendable {
    func insertRecommendation(
        scope: CoachScope,
        workoutSessionId: String?,
        workoutSessionExerciseId: String?,
        setEntryId: String?,
        type: String,
        payloadJSON: String
    ) throws -> String
}
