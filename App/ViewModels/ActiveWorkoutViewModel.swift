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
    private var liveActivityHealthThrottle: Int = 0
    /// Dedupes Live Activity pushes when only `AppleHealthWorkoutService` published properties change.
    private var lastLiveActivityHealthGlanceSignature: String?
    /// Shown in Live Activity briefly after rest hits zero (natural completion only).
    private var restAttentionExpiresAt: Date?
    private var scheduledRestEndWorkItem: DispatchWorkItem?
    private var pendingRestNotificationKey: String?
    private var lastWatchPushAt: Date = .distantPast

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
                await env.liveActivity.startIfNeeded(sessionId: sessionId, workoutStartedAt: sessionStartedAt)
                await pushLiveActivity()
            }
        }
    }

    func onDisappear() {
        tick?.cancel()
        tick = nil
    }

    /// Pushes an ActivityKit update when heart rate, energy, or the missing-BPM tip changes (skips if unchanged).
    func refreshLiveActivityIfHealthGlanceChanged() async {
        guard sessionStatus == .active, env.appleHealth.syncWorkoutsToHealthEnabled else { return }
        let sig = liveActivityHealthGlanceSignature()
        guard sig != lastLiveActivityHealthGlanceSignature else { return }
        await pushLiveActivity()
    }

    private func liveActivityHealthGlanceSignature() -> String {
        let h = env.appleHealth
        let bpm = h.latestHeartRateBpm.map(String.init) ?? "-"
        let kcal = h.cumulativeActiveEnergyHealthKitKcal.map { String(format: "%.2f", $0) } ?? "-"
        let tip = h.heartRateAvailabilityTipForLiveActivity() ?? ""
        let authEpoch = h.healthAuthorizationRefreshEpoch
        return "\(bpm)|\(kcal)|\(tip)|\(authEpoch)"
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
            pushWatchConnectivitySnapshot(force: true)
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
            cancelScheduledRestCompletion()
            if let tid = restTimerVisual?.timerId {
                RestTimerEndNotifier.cancel(timerId: tid)
            }
            Task { @MainActor in
                await env.appleHealth.onWorkoutFinished(sessionId: sessionId)
                await env.liveActivity.end()
            }
            reload()
            pushWatchIdleSnapshot()
        } catch {
            // ignore
        }
    }

    func discard() {
        env.appleHealth.onWorkoutDiscarded(sessionId: sessionId)
        try? env.workouts.discardSession(sessionId: sessionId)
        LoggyFeedback.workoutDiscarded()
        cancelScheduledRestCompletion()
        if let tid = restTimerVisual?.timerId {
            RestTimerEndNotifier.cancel(timerId: tid)
        }
        Task { @MainActor in await env.liveActivity.end() }
        reload()
    }

    func skipRest() {
        guard let snap = try? env.restTimers.activeTimer(for: sessionId) else { return }
        RestTimerEndNotifier.cancel(timerId: snap.id)
        cancelScheduledRestCompletion()
        pendingRestNotificationKey = nil
        try? env.restTimers.skipTimer(timerId: snap.id)
        LoggyFeedback.restSkipped()
        restCompletedFeedbackTimerId = nil
        restAttentionExpiresAt = nil
        refreshRest()
        Task { @MainActor in await pushLiveActivity() }
        pushWatchConnectivitySnapshot(force: true)
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
        // Lock screen elapsed + rest countdown animate in the widget via wall-clock anchors (`workoutStartedAt`, `restEndsAt`).
        // Push occasionally so HR/kcal stay plausible when Health sync is on.
        if sessionStatus == .active, env.appleHealth.syncWorkoutsToHealthEnabled {
            liveActivityHealthThrottle += 1
            if liveActivityHealthThrottle >= 30 {
                liveActivityHealthThrottle = 0
                Task { @MainActor in await pushLiveActivity() }
            }
        }
        if sessionStatus == .active {
            pushWatchConnectivitySnapshot(force: false)
        }
    }

    private func refreshRest() {
        let restSigBefore = liveRestSignatureForPush()
        defer {
            if sessionStatus == .active {
                let restSigAfter = liveRestSignatureForPush()
                if restSigBefore != restSigAfter {
                    Task { @MainActor in await pushLiveActivity() }
                }
            }
        }
        guard sessionStatus == .active else {
            cancelScheduledRestCompletion()
            pendingRestNotificationKey = nil
            restRemaining = nil
            restTimerVisual = nil
            restCompletedFeedbackTimerId = nil
            restAttentionExpiresAt = nil
            return
        }
        guard let snap = try? env.restTimers.activeTimer(for: sessionId),
              let ends = snap.endsAt
        else {
            cancelScheduledRestCompletion()
            pendingRestNotificationKey = nil
            restRemaining = nil
            restTimerVisual = nil
            restCompletedFeedbackTimerId = nil
            return
        }
        let newRemaining = RestTimerService.remainingSeconds(endsAt: ends)
        if snap.state == .running, (newRemaining ?? 0) <= 0 {
            completeNaturalRest(timerId: snap.id)
            return
        }

        restRemaining = newRemaining
        if let started = snap.startedAt {
            restAttentionExpiresAt = nil
            restTimerVisual = RestTimerVisual(timerId: snap.id, startedAt: started, endsAt: ends)
            if snap.state == .running, (newRemaining ?? 0) > 0 {
                scheduleRestEndAlarms(snap: snap, endsAt: ends)
            }
        } else {
            cancelScheduledRestCompletion()
            restTimerVisual = nil
        }
    }

    private func cancelScheduledRestCompletion() {
        scheduledRestEndWorkItem?.cancel()
        scheduledRestEndWorkItem = nil
    }

    /// Completes a running rest row in the DB, triggers haptics once, and starts the Live Activity “attention” window.
    private func completeNaturalRest(timerId: String) {
        if restCompletedFeedbackTimerId != timerId {
            restCompletedFeedbackTimerId = timerId
            LoggyFeedback.restTimerCompleted()
        }
        RestTimerEndNotifier.cancel(timerId: timerId)
        cancelScheduledRestCompletion()
        pendingRestNotificationKey = nil
        try? env.restTimers.completeExpiredRunningTimersIfNeeded(sessionId: sessionId)
        restAttentionExpiresAt = Date().addingTimeInterval(14)
        restRemaining = nil
        restTimerVisual = nil
    }

    private func scheduleRestEndAlarms(snap: RestTimerSnapshot, endsAt: Date) {
        cancelScheduledRestCompletion()
        guard snap.state == .running else { return }

        let notifyKey = "\(snap.id)|\(endsAt.timeIntervalSince1970)"
        if pendingRestNotificationKey != notifyKey {
            pendingRestNotificationKey = notifyKey
            RestTimerEndNotifier.scheduleIfNeeded(timerId: snap.id, endsAt: endsAt)
        }

        let interval = endsAt.timeIntervalSinceNow
        guard interval > 0 else { return }

        let capturedId = snap.id
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.scheduledRestEndWorkItem = nil
                guard self.sessionStatus == .active else { return }
                guard let cur = try? self.env.restTimers.activeTimer(for: self.sessionId),
                      cur.id == capturedId,
                      cur.state == .running,
                      let end = cur.endsAt,
                      end <= Date()
                else { return }
                self.completeNaturalRest(timerId: capturedId)
                // Explicit push: `refreshRest` defer does not run on this path (work item is outside `refreshRest`), and the next tick’s defer may see an unchanged signature vs `liveRestSignatureForPush`.
                Task { @MainActor in await self.pushLiveActivity() }
            }
        }
        scheduledRestEndWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
    }

    private func liveRestSignatureForPush() -> String {
        var base = LiveActivityElapsedLogic.restPushSignature(
            timerId: restTimerVisual?.timerId,
            restEndsAt: restTimerVisual?.endsAt,
            legacyRemainingSeconds: restTimerVisual == nil ? restRemaining : nil
        )
        if let att = restAttentionExpiresAt {
            base += "|att|\(att.timeIntervalSince1970)"
        }
        return base
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
        lastLiveActivityHealthGlanceSignature = liveActivityHealthGlanceSignature()
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
                nextPreview = LiveActivitySetPreviewFormatter.nextPlannedSetLine(
                    exercises: exercises,
                    card: card,
                    currentSetId: cur.id
                )
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
            workoutStartedAt: LiveActivityElapsedLogic.sanitizedWorkoutStartedAt(sessionStartedAt),
            restRemainingSeconds: restRemInt,
            restEndsAt: restEnd,
            restStartedAt: restTimerVisual?.startedAt,
            restProgress: restProgress,
            restAttentionExpiresAt: restAttentionExpiresAt,
            liveSessionExerciseId: wse,
            liveSetEntryId: setId,
            currentSetTitle: setTitle,
            nextSetPreview: nextPreview,
            previousDisplayCompact: prevDisp,
            currentKgDisplay: kgDisp,
            currentRepsDisplay: repsDisp,
            heartBpm: env.appleHealth.syncWorkoutsToHealthEnabled ? env.appleHealth.latestHeartRateBpm : nil,
            activeKcalDisplay: kcalDisplay,
            heartRateTip: env.appleHealth.syncWorkoutsToHealthEnabled
                ? env.appleHealth.heartRateAvailabilityTipForLiveActivity()
                : nil
        )
    }

    private func setTitleForLiveActivity(_ set: SetRowModel) -> String {
        switch set.setType {
        case .warmup: return "W"
        default: return "Set \(set.setIndex + 1)"
        }
    }

    // MARK: - Apple Watch mirror

    func pushWatchIdleSnapshot() {
        env.phoneWatchBridge.pushSnapshot(
            WatchActiveWorkoutSnapshot(
                sessionId: sessionId,
                workoutStartedAt: nil,
                phase: .idle,
                currentExerciseName: "",
                completedSetCount: 0,
                restEndsAt: nil,
                restStartedAt: nil,
            healthSyncEnabled: false
        )
        )
    }

    /// Flushes mirror state after returning from Settings / Health so Watch Connectivity picks up immediately.
    func pushWatchSnapshotAfterForeground() {
        pushWatchConnectivitySnapshot(force: true)
    }

    private func makeWatchSnapshot() -> WatchActiveWorkoutSnapshot {
        WatchActiveWorkoutSnapshot(
            sessionId: sessionId,
            workoutStartedAt: sessionStartedAt.map { ISO8601UTC.string(from: $0) },
            phase: sessionStatus == .active ? .active : .idle,
            currentExerciseName: currentExerciseName(),
            completedSetCount: completedSetCount,
            restEndsAt: restTimerVisual.map { ISO8601UTC.string(from: $0.endsAt) },
            restStartedAt: restTimerVisual.map { ISO8601UTC.string(from: $0.startedAt) },
            healthSyncEnabled: env.appleHealth.syncWorkoutsToHealthEnabled,
            watchRunsHealthKitSession: env.appleHealth.watchHealthKitSnapshotHint
        )
    }

    /// ~1 Hz max unless `force` (reload, skip rest, etc.).
    private func pushWatchConnectivitySnapshot(force: Bool) {
        guard sessionStatus == .active else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastWatchPushAt) < 0.9 { return }
        lastWatchPushAt = now
        env.phoneWatchBridge.pushSnapshot(makeWatchSnapshot())
    }

}
