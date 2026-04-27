import Combine
import Foundation
import GRDB

public struct RestTimerVisual: Equatable, Sendable {
    public var timerId: String
    public var startedAt: Date
    public var endsAt: Date
}

enum ActiveWorkoutFocus {
    /// First exercise with an incomplete set; current set is first incomplete. If all complete, last exercise and its last set.
    static func currentSessionExerciseAndSet(in exercises: [SessionExerciseCard]) -> (sessionExerciseId: String, setId: String)? {
        for card in exercises {
            if let s = card.sets.first(where: { $0.status != .completed }) {
                return (card.id, s.id)
            }
        }
        if let last = exercises.last, let s = last.sets.last {
            return (last.id, s.id)
        }
        return nil
    }
}

@MainActor
final class ActiveWorkoutViewModel: ObservableObject {
    let sessionId: String
    private let env: AppEnvironment

    @Published private(set) var sessionTitle: String = ""
    @Published private(set) var sessionStatus: WorkoutSessionStatus = .active
    @Published private(set) var exercises: [SessionExerciseCard] = []

    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var totalVolume: Double = 0
    @Published private(set) var completedSetCount: Int = 0
    @Published private(set) var restRemaining: Int?
    @Published private(set) var restTimerVisual: RestTimerVisual?
    @Published private(set) var suggestedNextExercise: ExerciseSummary?

    private var tick: AnyCancellable?

    init(sessionId: String, env: AppEnvironment) {
        self.sessionId = sessionId
        self.env = env
    }

    func onAppear() {
        reload()
        tick?.cancel()
        tick = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.tickSecond() }
            }

        if sessionStatus == .active {
            Task { @MainActor in
                await env.liveActivity.startIfNeeded(sessionId: sessionId)
                await pushLiveActivity()
            }
        }
    }

    func onDisappear() {
        tick?.cancel()
        tick = nil
    }

    func reload() {
        do {
            let meta = try env.workouts.loadSessionForEdit(sessionId: sessionId)
            sessionStatus = meta.status
            sessionTitle = meta.title ?? ""

            exercises = try env.workouts.sessionExercises(sessionId: sessionId)

            let started = try env.database.pool.read { db in
                try String.fetchOne(db, sql: "SELECT started_at FROM workout_session WHERE id = ?", arguments: [sessionId])
            }
            if let started, let d = ISO8601UTC.date(from: started) {
                elapsedSeconds = max(0, Int(Date().timeIntervalSince(d)))
            }

            if let totals = try env.database.pool.read({ db in
                try Row.fetchOne(
                    db,
                    sql: "SELECT total_volume_kg_cache, total_set_count_cache FROM workout_session WHERE id = ?",
                    arguments: [sessionId]
                )
            }) {
                totalVolume = totals["total_volume_kg_cache"]
                completedSetCount = totals["total_set_count_cache"]
            }

            refreshRest()

            let excluding = Set(exercises.map(\.exerciseId))
            let focus = ActiveWorkoutFocus.currentSessionExerciseAndSet(in: exercises)
            let afterCanon = focus.flatMap { fid in exercises.first(where: { $0.id == fid.sessionExerciseId })?.exerciseId }
            suggestedNextExercise = try? env.nextExerciseSuggestion.suggestFollowing(
                afterExerciseId: afterCanon,
                excludingExerciseIds: excluding
            )

            if let focus {
                try? env.workouts.syncActiveWorkoutFocus(
                    sessionId: sessionId,
                    sessionExerciseId: focus.sessionExerciseId,
                    setEntryId: focus.setId
                )
            } else {
                try? env.workouts.syncActiveWorkoutFocus(sessionId: sessionId, sessionExerciseId: nil, setEntryId: nil)
            }
        } catch {
            // keep UI stable on read errors
        }
    }

    func currentExerciseIndex() -> Int? {
        guard let wse = ActiveWorkoutFocus.currentSessionExerciseAndSet(in: exercises)?.sessionExerciseId else { return nil }
        return exercises.firstIndex(where: { $0.id == wse })
    }

    func isCurrentExercise(cardId: String) -> Bool {
        ActiveWorkoutFocus.currentSessionExerciseAndSet(in: exercises)?.sessionExerciseId == cardId
    }

    func isCurrentSet(sessionExerciseId: String, setId: String) -> Bool {
        guard let cur = ActiveWorkoutFocus.currentSessionExerciseAndSet(in: exercises) else { return false }
        return cur.sessionExerciseId == sessionExerciseId && cur.setId == setId
    }

    func updateSessionTitle(_ text: String) {
        try? env.workouts.updateSessionTitle(sessionId: sessionId, title: text)
        sessionTitle = text
    }

    func addExercise(exerciseId: String) {
        try? env.workouts.addExercise(sessionId: sessionId, exerciseId: exerciseId)
        reload()
        Task { @MainActor in await pushLiveActivity() }
    }

    func addSet(sessionExerciseId: String, cloneFromSetId: String?) {
        try? env.workouts.addSet(sessionExerciseId: sessionExerciseId, cloneFromSetId: cloneFromSetId)
        reload()
        Task { @MainActor in await pushLiveActivity() }
    }

    func updateSet(setId: String, weight: Double?, reps: Int?, distanceKm: Double?, duration: Int?, rpe: Double?) {
        try? env.workouts.updateSet(
            setId: setId,
            weightKg: weight,
            reps: reps,
            distanceKm: distanceKm,
            durationSeconds: duration,
            rpe: rpe
        )
        reload()
        Task { @MainActor in await pushLiveActivity() }
    }

    func completeSet(sessionExerciseId: String, setId: String) {
        let prevReps = exercises
            .first(where: { $0.id == sessionExerciseId })?
            .sets.first(where: { $0.id == setId })?
            .reps

        do {
            try env.workouts.completeSet(sessionId: sessionId, sessionExerciseId: sessionExerciseId, setId: setId)
            let newReps = try env.database.pool.read { db in
                try Int.fetchOne(db, sql: "SELECT reps FROM set_entry WHERE id = ?", arguments: [setId])
            }
            env.coachService.recordIntraSessionRepDropoff(
                workoutSessionId: sessionId,
                workoutSessionExerciseId: sessionExerciseId,
                setEntryId: setId,
                previousReps: prevReps,
                currentReps: newReps
            )
        } catch {
            // ignore
        }
        reload()
        Task { @MainActor in await pushLiveActivity() }
    }

    func deleteSet(setId: String) {
        try? env.workouts.deleteSet(setId: setId)
        reload()
        Task { @MainActor in await pushLiveActivity() }
    }

    func updateNotes(sessionExerciseId: String, notes: String) {
        try? env.workouts.updateSessionExerciseNotes(sessionExerciseId: sessionExerciseId, notes: notes)
        reload()
    }

    func updateRestTarget(sessionExerciseId: String, seconds: Int) {
        try? env.workouts.updateTargetRest(sessionExerciseId: sessionExerciseId, seconds: seconds)
        reload()
    }

    func finish() {
        do {
            try env.workouts.finishSession(sessionId: sessionId)
            Task { @MainActor in await env.liveActivity.end() }
        } catch {
            // ignore
        }
    }

    func discard() {
        try? env.workouts.discardSession(sessionId: sessionId)
        Task { @MainActor in await env.liveActivity.end() }
    }

    func skipRest() {
        guard let snap = try? env.restTimers.activeTimer(for: sessionId) else { return }
        try? env.restTimers.skipTimer(timerId: snap.id)
        refreshRest()
        Task { @MainActor in await pushLiveActivity() }
    }

    private func tickSecond() {
        if sessionStatus == .active,
           let started = try? env.database.pool.read({ db in
               try String.fetchOne(db, sql: "SELECT started_at FROM workout_session WHERE id = ?", arguments: [sessionId])
           }),
           let d = ISO8601UTC.date(from: started)
        {
            elapsedSeconds = max(0, Int(Date().timeIntervalSince(d)))
        }
        refreshRest()
        Task { @MainActor in await pushLiveActivity() }
    }

    private func refreshRest() {
        guard sessionStatus == .active else {
            restRemaining = nil
            restTimerVisual = nil
            return
        }
        guard let snap = try? env.restTimers.activeTimer(for: sessionId),
              let ends = snap.endsAt
        else {
            restRemaining = nil
            restTimerVisual = nil
            return
        }
        restRemaining = RestTimerService.remainingSeconds(endsAt: ends)
        if let started = snap.startedAt {
            restTimerVisual = RestTimerVisual(timerId: snap.id, startedAt: started, endsAt: ends)
        } else {
            restTimerVisual = nil
        }
    }

    private func currentExerciseName() -> String {
        if let wse = ActiveWorkoutFocus.currentSessionExerciseAndSet(in: exercises)?.sessionExerciseId,
           let name = exercises.first(where: { $0.id == wse })?.displayName
        {
            return name
        }
        return exercises.first?.displayName ?? "Workout"
    }

    private func pushLiveActivity() async {
        await env.liveActivity.update(
            elapsedSeconds: elapsedSeconds,
            completedSetCount: completedSetCount,
            currentExerciseName: currentExerciseName(),
            restRemainingSeconds: restRemaining
        )
    }
}
