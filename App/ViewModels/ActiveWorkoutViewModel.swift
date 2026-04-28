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
    @Published private(set) var totalRepCount: Int = 0
    @Published private(set) var restRemaining: Int?
    @Published private(set) var restTimerVisual: RestTimerVisual?
    @Published private(set) var suggestedNextExercise: ExerciseSummary?
    @Published private(set) var sessionStartedAt: Date?

    private var tick: AnyCancellable?
    /// Fires rest-complete feedback once per rest timer when wall clock passes `ends_at` while the row is still `running`.
    private var restCompletedFeedbackTimerId: String?

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

            let timingRow = try env.database.pool.read { db in
                try Row.fetchOne(
                    db,
                    sql: """
                        SELECT started_at, ended_at, total_duration_seconds_cache
                        FROM workout_session WHERE id = ?
                        """,
                    arguments: [sessionId]
                )
            }
            if let timingRow {
                let startedStr: String? = timingRow["started_at"]
                let endedStr: String? = timingRow["ended_at"]
                let durCache: Int? = {
                    if let v: Int = timingRow["total_duration_seconds_cache"] { return v }
                    if let v: Int64 = timingRow["total_duration_seconds_cache"] { return Int(v) }
                    return nil
                }()
                if let startedStr, let start = ISO8601UTC.date(from: startedStr) {
                    sessionStartedAt = start
                    if sessionStatus == .active {
                        elapsedSeconds = max(0, Int(Date().timeIntervalSince(start)))
                    } else if let endedStr, !endedStr.isEmpty, let end = ISO8601UTC.date(from: endedStr) {
                        elapsedSeconds = max(0, Int(end.timeIntervalSince(start)))
                    } else if let durCache {
                        elapsedSeconds = max(0, durCache)
                    } else {
                        elapsedSeconds = 0
                    }
                } else {
                    sessionStartedAt = nil
                    elapsedSeconds = 0
                }
            } else {
                sessionStartedAt = nil
                elapsedSeconds = 0
            }

            if let totals = try env.database.pool.read({ db in
                try Row.fetchOne(
                    db,
                    sql: """
                        SELECT total_volume_kg_cache, total_set_count_cache, total_rep_count_cache
                        FROM workout_session WHERE id = ?
                        """,
                    arguments: [sessionId]
                )
            }) {
                totalVolume = totals["total_volume_kg_cache"]
                completedSetCount = totals["total_set_count_cache"]
                if let n = totals["total_rep_count_cache"] as? Int64 {
                    totalRepCount = Int(n)
                } else if let n = totals["total_rep_count_cache"] as? Int {
                    totalRepCount = n
                } else {
                    totalRepCount = 0
                }
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
            sessionStartedAt = nil
            // keep UI stable on read errors
        }
        if sessionStatus == .active {
            Task { @MainActor in await pushLiveActivity() }
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
    }

    func addExercises(exerciseIds: [String]) {
        for id in exerciseIds {
            try? env.workouts.addExercise(sessionId: sessionId, exerciseId: id)
        }
        reload()
    }

    func addSet(sessionExerciseId: String, cloneFromSetId: String?) {
        try? env.workouts.addSet(sessionExerciseId: sessionExerciseId, cloneFromSetId: cloneFromSetId)
        reload()
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
    }

    func completeSet(sessionExerciseId: String, setId: String) {
        let prevReps = exercises
            .first(where: { $0.id == sessionExerciseId })?
            .sets.first(where: { $0.id == setId })?
            .reps

        do {
            try env.workouts.completeSet(sessionId: sessionId, sessionExerciseId: sessionExerciseId, setId: setId)
            LoggyFeedback.setCompleted()
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
    }

    func toggleSetCompletion(sessionExerciseId: String, setId: String) {
        let completed = exercises
            .first(where: { $0.id == sessionExerciseId })?
            .sets.first(where: { $0.id == setId })?
            .status == .completed
        if completed == true {
            try? env.workouts.uncompleteSet(sessionId: sessionId, sessionExerciseId: sessionExerciseId, setId: setId)
            LoggyFeedback.setUncompleted()
            reload()
        } else {
            completeSet(sessionExerciseId: sessionExerciseId, setId: setId)
        }
    }

    func deleteSet(setId: String) {
        try? env.workouts.deleteSet(setId: setId)
        reload()
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
            LoggyFeedback.workoutFinishedSaved()
            Task { @MainActor in
                await env.appleHealth.onWorkoutFinished(sessionId: sessionId)
                await env.liveActivity.end()
            }
        } catch {
            // ignore
        }
    }

    func discard() {
        env.appleHealth.onWorkoutDiscarded(sessionId: sessionId)
        try? env.workouts.discardSession(sessionId: sessionId)
        LoggyFeedback.workoutDiscarded()
        Task { @MainActor in await env.liveActivity.end() }
    }

    func skipRest() {
        guard let snap = try? env.restTimers.activeTimer(for: sessionId) else { return }
        try? env.restTimers.skipTimer(timerId: snap.id)
        LoggyFeedback.restSkipped()
        restCompletedFeedbackTimerId = nil
        refreshRest()
        Task { @MainActor in await pushLiveActivity() }
    }

    func adjustRestTimer(by deltaSeconds: Int) {
        try? env.restTimers.adjustRunningTimer(sessionId: sessionId, deltaSeconds: deltaSeconds)
        LoggyFeedback.restAdjusted()
        reload()
    }

    func moveExercise(fromIndex: Int, direction: Int) {
        var ids = exercises.map(\.id)
        let j = fromIndex + direction
        guard ids.indices.contains(fromIndex), ids.indices.contains(j) else { return }
        ids.swapAt(fromIndex, j)
        try? env.workouts.reorderExercises(sessionId: sessionId, orderedExerciseRowIds: ids)
        reload()
    }

    func removeSessionExercise(sessionExerciseId: String) {
        try? env.workouts.removeSessionExercise(sessionId: sessionId, sessionExerciseId: sessionExerciseId)
        reload()
    }

    /// Keeps set rows; new exercise must match the slot’s `exercise_mode` (enforced in repository).
    func replaceSessionExercise(sessionExerciseId: String, newExerciseId: String) {
        do {
            try env.workouts.replaceSessionExercise(sessionId: sessionId, sessionExerciseId: sessionExerciseId, newExerciseId: newExerciseId)
            reload()
            if sessionStatus == .active {
                Task { @MainActor in await pushLiveActivity() }
            }
        } catch {
            // UI only offers same-mode replacements; ignore unexpected failures.
        }
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
        if sessionStatus == .active {
            Task { @MainActor in await pushLiveActivity() }
        }
    }

    private func refreshRest() {
        guard sessionStatus == .active else {
            restRemaining = nil
            restTimerVisual = nil
            restCompletedFeedbackTimerId = nil
            return
        }
        guard let snap = try? env.restTimers.activeTimer(for: sessionId),
              let ends = snap.endsAt
        else {
            restRemaining = nil
            restTimerVisual = nil
            restCompletedFeedbackTimerId = nil
            return
        }
        let newRemaining = RestTimerService.remainingSeconds(endsAt: ends)
        if snap.state == .running, (newRemaining ?? 0) <= 0 {
            if restCompletedFeedbackTimerId != snap.id {
                restCompletedFeedbackTimerId = snap.id
                LoggyFeedback.restTimerCompleted()
            }
            try? env.restTimers.completeExpiredRunningTimersIfNeeded(sessionId: sessionId)
            restRemaining = nil
            restTimerVisual = nil
            return
        }

        restRemaining = newRemaining
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
        guard sessionStatus == .active else { return }
        await env.liveActivity.update(sessionId: sessionId, state: makeLiveActivityContentState())
    }

    /// Reloads session state and returns Live Activity payload (e.g. after a lock-screen deep link while the workout screen is not mounted).
    @MainActor
    static func liveActivitySnapshotAfterMutation(sessionId: String, env: AppEnvironment) -> WorkoutActivityAttributes.ContentState {
        let vm = ActiveWorkoutViewModel(sessionId: sessionId, env: env)
        vm.reload()
        return vm.makeLiveActivityContentState()
    }

    private func makeLiveActivityContentState() -> WorkoutActivityAttributes.ContentState {
        let name = currentExerciseName()
        let focus = ActiveWorkoutFocus.currentSessionExerciseAndSet(in: exercises)
        var wse: String?
        var setId: String?
        var setTitle = ""
        var nextPreview = "—"
        var prevDisp = "—"
        var kgDisp = "—"
        var repsDisp = "—"

        if let focus {
            wse = focus.sessionExerciseId
            setId = focus.setId
            if let card = exercises.first(where: { $0.id == focus.sessionExerciseId }),
               let cur = card.sets.first(where: { $0.id == focus.setId })
            {
                setTitle = setTitleForLiveActivity(cur)
                prevDisp = cur.previousDisplay
                switch card.exerciseMode {
                case .weightReps:
                    if let w = cur.weightKg {
                        kgDisp = String(format: "%.1f", w)
                    }
                    repsDisp = cur.reps.map(String.init) ?? "—"
                case .bodyweightReps:
                    kgDisp = "—"
                    repsDisp = cur.reps.map(String.init) ?? "—"
                case .duration:
                    kgDisp = "—"
                    repsDisp = cur.durationSeconds.map(String.init) ?? "—"
                case .distanceDuration:
                    if let d = cur.distanceKm {
                        kgDisp = String(format: "%.2f km", d)
                    } else {
                        kgDisp = "—"
                    }
                    repsDisp = cur.durationSeconds.map { "\($0)s" } ?? "—"
                }
                nextPreview = nextSetPreviewText(card: card, currentSetId: cur.id)
            }
        }

        var kcalDisplay: String?
        if env.appleHealth.syncWorkoutsToHealthEnabled, let start = sessionStartedAt {
            if let hk = env.appleHealth.cumulativeActiveEnergyHealthKitKcal, hk > 0.5 {
                kcalDisplay = "\(Int(hk)) kcal"
            } else {
                let est = env.appleHealth.estimatedSessionEnergyKcalSoFar(sessionStartedAt: start)
                kcalDisplay = "~\(Int(est)) kcal"
            }
        }

        var restProgress: Double?
        if let v = restTimerVisual {
            let total = v.endsAt.timeIntervalSince(v.startedAt)
            if total > 0 {
                let elapsed = Date().timeIntervalSince(v.startedAt)
                restProgress = min(1, max(0, elapsed / total))
            }
        }

        let restEnd = restTimerVisual?.endsAt
        // When we have wall-clock `restEndsAt`, the widget uses `TimelineView` only — omit integer seconds to avoid conflicting with `.timer`-style jumps.
        let restRemInt: Int? = (restEnd != nil) ? nil : restRemaining

        return WorkoutActivityAttributes.ContentState(
            elapsedSeconds: elapsedSeconds,
            completedSetCount: completedSetCount,
            currentExerciseName: name,
            restRemainingSeconds: restRemInt,
            restEndsAt: restEnd,
            restStartedAt: restTimerVisual?.startedAt,
            restProgress: restProgress,
            liveSessionExerciseId: wse,
            liveSetEntryId: setId,
            currentSetTitle: setTitle,
            nextSetPreview: nextPreview,
            previousDisplayCompact: prevDisp,
            currentKgDisplay: kgDisp,
            currentRepsDisplay: repsDisp,
            heartBpm: env.appleHealth.syncWorkoutsToHealthEnabled ? env.appleHealth.latestHeartRateBpm : nil,
            activeKcalDisplay: kcalDisplay
        )
    }

    private func setTitleForLiveActivity(_ set: SetRowModel) -> String {
        switch set.setType {
        case .warmup: return "W"
        default: return "Set \(set.setIndex + 1)"
        }
    }

    private func nextSetPreviewText(card: SessionExerciseCard, currentSetId: String) -> String {
        guard let si = card.sets.firstIndex(where: { $0.id == currentSetId }) else { return "—" }
        if si + 1 < card.sets.count {
            let n = card.sets[si + 1]
            return "Next: \(setTitleForLiveActivity(n))"
        }
        if let ci = exercises.firstIndex(where: { $0.id == card.id }), ci + 1 < exercises.count {
            let nex = exercises[ci + 1]
            if let fs = nex.sets.first {
                let short: String = {
                    let n = nex.displayName
                    return n.count > 22 ? String(n.prefix(22)) + "…" : n
                }()
                return "Next: \(short) · \(setTitleForLiveActivity(fs))"
            }
        }
        return "Next: —"
    }
}
