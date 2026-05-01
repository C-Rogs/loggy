import Combine
import Foundation
import HealthKit
import WatchConnectivity

public struct HeartRateSamplePoint: Hashable, Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let bpm: Double

    public init(date: Date, bpm: Double) {
        self.date = date
        self.bpm = bpm
    }
}

/// Bridges active Loggy sessions to Apple Health: traditional strength `HKWorkout` (Exercise ring / Fitness),
/// estimated active energy (Move ring), and live heart rate.
///
/// **Hevy-style HR:** Live BPM comes from the Watch **live workout** (``HKLiveWorkoutSession`` + ``HKLiveWorkoutBuilder``) over **Watch Connectivity**. HealthKit HR queries are fallback only.
///
/// **Watch-first HK:** With LoggyWatch installed, the phone delays ``HKWorkoutBuilder`` so the Watch can start ``HKLiveWorkoutSession`` first (same idea as other strength-training apps).
/// Consumer AirPods do not expose heart rate to HealthKit.
@MainActor
final class AppleHealthWorkoutService: ObservableObject {
    static let syncEnabledKey = "loggyAppleHealthWorkoutSync"

    /// Who persists the active-session HealthKit workout (at most one).
    private enum HealthKitWorkoutWriter: Sendable {
        case none
        case phoneBuilder
        case watchBuilder
    }

    weak var phoneWatchBridge: PhoneWatchSessionBridge?

    private let store = HKHealthStore()
    private let workouts: WorkoutSessionRepository

    private var workoutBuilder: HKWorkoutBuilder?
    private var attachedSessionId: String?
    private var sessionStart: Date?
    private var heartAnchor: HKQueryAnchor?
    private var heartQuery: HKAnchoredObjectQuery?
    /// Delivers updates when **new** heart-rate samples land in Health (covers gaps where ``HKAnchoredObjectQuery`` stalls until another writer touches HR—same symptom as running two workout apps).
    private var heartObserverQuery: HKObserverQuery?
    /// Fallback poll so BPM updates even if anchored + observer miss deliveries during a session.
    private var heartRatePollTimer: AnyCancellable?
    /// End time of the HR sample currently reflected in ``latestHeartRateBpm`` — anchored batches are unordered; never regress to an older reading.
    private var lastAppliedHeartRateSampleEnd: Date = .distantPast
    private var liveEnergyTimer: AnyCancellable?
    private var healthKitWriter: HealthKitWorkoutWriter = .none {
        didSet {
            if oldValue != healthKitWriter {
                objectWillChange.send()
            }
        }
    }
    /// iPhone-side **mirrored** session when the Watch runs the primary ``HKWorkoutSession`` (see ``HKHealthStore/workoutSessionMirroringStartHandler``).
    private var mirroredWorkoutSession: HKWorkoutSession?
    private let mirroredWorkoutSessionDelegate = LoggyMirroredWorkoutSessionDelegate()

    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!

    @Published private(set) var latestHeartRateBpm: Int?
    /// Bumped after re-reading HealthKit authorization so UI/Live Activity pick up Settings changes without an app relaunch.
    @Published private(set) var healthAuthorizationRefreshEpoch: UInt = 0
    /// Merged HealthKit cumulative active energy for the current workout window (efficient 30s poll).
    @Published private(set) var cumulativeActiveEnergyHealthKitKcal: Double?
    @Published private(set) var isHealthDataAvailable: Bool
    @Published private(set) var syncWorkoutsToHealthEnabled: Bool
    /// True while waiting for LoggyWatch to confirm ``hkReady`` (queued ``prepareHK`` + handshake timeout).
    @Published private(set) var isAwaitingWatchHealthKitAck: Bool = false

    /// For Watch snapshot JSON: `nil` = iPhone hasn’t chosen Watch vs phone HK writer yet; don’t start Watch ``HKWorkoutSession`` from a pending `startWatchApp` wake.
    var watchHealthKitSnapshotHint: Bool? {
        switch healthKitWriter {
        case .watchBuilder: return true
        case .phoneBuilder: return false
        case .none: return nil
        }
    }

    /// Shown on the lock screen Live Activity and active-workout summary when Health sync is on but no BPM sample has arrived.
    ///
    /// **Do not use** ``authorizationStatus(for:)`` for heart rate here. That API reflects **sharing** (write) semantics
    /// and often reports ``HKAuthorizationStatus/sharingDenied`` for heart rate even when the user has granted **read**
    /// access in Health → Sharing → Apps → Loggy—which wrongly showed “turn on heart rate” while reads actually work.
    func heartRateAvailabilityTipForLiveActivity() -> String? {
        guard syncWorkoutsToHealthEnabled, latestHeartRateBpm == nil else { return nil }
        guard isHealthDataAvailable else {
            return "Heart rate isn’t available on this device."
        }
        if isAwaitingWatchHealthKitAck {
            return "Connecting to Apple Watch for heart rate…"
        }
        // Don’t blame “Health samples” — live BPM is Watch → phone, not HK mirror latency.
        if WCSession.isSupported(), WCSession.default.isWatchAppInstalled,
           let start = sessionStart, Date().timeIntervalSince(start) < 120
        {
            return nil
        }
        return "Waiting for heart rate from Apple Watch… Keep Loggy open on the Watch if you see a prompt."
    }

    init(workouts: WorkoutSessionRepository) {
        self.workouts = workouts
        isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()
        syncWorkoutsToHealthEnabled = UserDefaults.standard.object(forKey: Self.syncEnabledKey) as? Bool ?? false

        store.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in
                self?.retainMirroredWorkoutSession(session)
            }
        }
    }

    func setSyncWorkoutsToHealthEnabled(_ enabled: Bool) {
        guard enabled != syncWorkoutsToHealthEnabled else { return }
        syncWorkoutsToHealthEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.syncEnabledKey)
        if enabled {
            Task { await requestAuthorization() }
        } else {
            discardBuilderOnly()
            stopHeartRateQuery()
            stopLiveEnergyPolling()
            latestHeartRateBpm = nil
            cumulativeActiveEnergyHealthKitKcal = nil
        }
    }

    func requestAuthorization() async {
        guard isHealthDataAvailable else { return }
        let toShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            energyType,
        ]
        let toRead: Set<HKObjectType> = [heartRateType, energyType]
        do {
            try await store.requestAuthorization(toShare: toShare, read: toRead)
            healthAuthorizationRefreshEpoch &+= 1
            objectWillChange.send()
        } catch {
            // Denied or restricted; user can retry from Settings.
        }
    }

    /// For Settings: explains when iOS will not show another Health sheet (common after reinstall / prior choices) and returns text for an alert in that case.
    func requestWorkoutHealthAccessFromSettings() async -> String? {
        guard isHealthDataAvailable else {
            return "Apple Health isn’t available on this device."
        }
        let toShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            energyType,
        ]
        let toRead: Set<HKObjectType> = [heartRateType, energyType]

        let status = await withCheckedContinuation { (cont: CheckedContinuation<HKAuthorizationRequestStatus, Never>) in
            store.getRequestStatusForAuthorization(toShare: toShare, read: toRead) { status, _ in
                cont.resume(returning: status)
            }
        }

        switch status {
        case .shouldRequest:
            do {
                try await store.requestAuthorization(toShare: toShare, read: toRead)
                healthAuthorizationRefreshEpoch &+= 1
                objectWillChange.send()
                return nil
            } catch {
                return "Couldn’t request access. Enable Workouts, Active Energy, and Heart Rate under Settings → Privacy & Security → Health → Loggy."
            }
        case .unknown:
            fallthrough
        case .unnecessary:
            healthAuthorizationRefreshEpoch &+= 1
            objectWillChange.send()
            return """
            iOS won’t show another permissions sheet for these data types (they were already requested). \
            Open the Health app → Sharing → Apps → Loggy and turn on Strength Training workouts, Active Energy, and Heart Rate. \
            You can also use Settings → Privacy & Security → Health → Loggy.
            """
        @unknown default:
            do {
                try await store.requestAuthorization(toShare: toShare, read: toRead)
                healthAuthorizationRefreshEpoch &+= 1
                objectWillChange.send()
                return nil
            } catch {
                return "Couldn’t update Health access. Try Settings → Privacy & Security → Health → Loggy."
            }
        }
    }

    /// Call when the app returns to foreground so Health permission changes in Settings / Health app refresh without restarting Loggy.
    func refreshAuthorizationAndRestartHeartQuery(sessionId: String, sessionStartedAt: Date?) async {
        guard syncWorkoutsToHealthEnabled, isHealthDataAvailable else { return }
        await requestAuthorization()
        guard attachedSessionId == sessionId else { return }
        let start = sessionStartedAt ?? sessionStart
        guard let start else { return }
        sessionStart = start
        heartAnchor = nil
        stopHeartRateQuery()
        startHeartRateQuery(from: start)
        startLiveEnergyPolling()
    }

    /// Watch ``HKLiveWorkoutBuilder`` → WC — always wins over HealthKit poll (same clock as on-watch workout UI).
    func applyLiveHeartRateFromWatch(bpm: Int, measuredAt: Date) {
        guard syncWorkoutsToHealthEnabled, attachedSessionId != nil else { return }
        latestHeartRateBpm = bpm
        lastAppliedHeartRateSampleEnd = measuredAt
    }

    func activeWorkoutScreenAppeared(sessionId: String, sessionStartedAt: Date) {
        guard isHealthDataAvailable, syncWorkoutsToHealthEnabled else { return }

        Task { await requestAuthorization() }

        if attachedSessionId != sessionId {
            discardBuilderOnly()
            stopHeartRateQuery()
            heartAnchor = nil
            attachedSessionId = sessionId
            sessionStart = sessionStartedAt
            healthKitWriter = .none
            Task { await self.coordinateHealthKitWriter(sessionId: sessionId, sessionStartedAt: sessionStartedAt) }
        } else if sessionStart != sessionStartedAt {
            sessionStart = sessionStartedAt
        }

        startHeartRateQuery(from: sessionStartedAt)
        startLiveEnergyPolling()
    }

    private func coordinateHealthKitWriter(sessionId: String, sessionStartedAt: Date) async {
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            healthKitWriter = .phoneBuilder
            beginWorkoutBuilder(sessionStartedAt: sessionStartedAt)
            return
        }

        let watchInstalled = WCSession.isSupported() && WCSession.default.isWatchAppInstalled
        if !watchInstalled {
            healthKitWriter = .phoneBuilder
            beginWorkoutBuilder(sessionStartedAt: sessionStartedAt)
            return
        }

        isAwaitingWatchHealthKitAck = true
        objectWillChange.send()

        await launchCompanionWatchAppViaHealthKit()

        let watchOwns = await phoneWatchBridge?.requestWatchOwnsHealthWorkout(
            sessionId: sessionId,
            sessionStartedAt: sessionStartedAt
        ) ?? false

        isAwaitingWatchHealthKitAck = false
        objectWillChange.send()

        if watchOwns {
            healthKitWriter = .watchBuilder
        } else {
            healthKitWriter = .phoneBuilder
            beginWorkoutBuilder(sessionStartedAt: sessionStartedAt)
        }
    }

    func activeWorkoutScreenDisappeared() {
        stopHeartRateQuery()
        stopLiveEnergyPolling()
    }

    /// MET-based running kcal for the session so far (fallback when HealthKit cumulative is empty).
    func estimatedSessionEnergyKcalSoFar(sessionStartedAt: Date, now: Date = Date()) -> Double {
        let hours = max(now.timeIntervalSince(sessionStartedAt) / 3600.0, 1.0 / 3600.0)
        let bodyMassKg = 75.0
        let met: Double = 5.0
        let kcalPerHour = (met * 3.5 * bodyMassKg) / 200.0 * 60.0
        return kcalPerHour * hours
    }

    /// Call after `finishSession` succeeds so `ended_at` exists for the retroactive path.
    func onWorkoutFinished(sessionId: String) async {
        guard isHealthDataAvailable, syncWorkoutsToHealthEnabled else { return }
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }

        if healthKitWriter == .watchBuilder {
            stopHeartRateQuery()
            stopLiveEnergyPolling()
            await phoneWatchBridge?.requestWatchFinishHealthWorkout(endedAt: Date())
            clearAttachment()
            return
        }

        if attachedSessionId == sessionId, let builder = workoutBuilder, let start = sessionStart {
            stopHeartRateQuery()
            stopLiveEnergyPolling()
            let end = Date()
            await finishBuilder(builder, start: start, end: end)
            clearAttachment()
            return
        }

        stopLiveEnergyPolling()
        guard let timing = try? workouts.sessionHealthKitTiming(sessionId: sessionId),
              let ended = timing.endedAt
        else { return }
        await recordRetroactiveWorkout(startedAt: timing.startedAt, endedAt: ended)
    }

    func onWorkoutDiscarded(sessionId: String) {
        guard attachedSessionId == sessionId else { return }
        if healthKitWriter == .watchBuilder {
            Task { await self.phoneWatchBridge?.requestWatchDiscardHealthWorkout() }
        } else {
            workoutBuilder?.discardWorkout()
            workoutBuilder = nil
        }
        stopHeartRateQuery()
        stopLiveEnergyPolling()
        clearAttachment()
    }

    /// Heart rate samples from Health for the session’s `started_at`…`ended_at` window (empty if unavailable or none stored).
    func heartRateSamplesBpm(sessionId: String) async -> [HeartRateSamplePoint] {
        guard isHealthDataAvailable else { return [] }
        guard let timing = try? workouts.sessionHealthKitTiming(sessionId: sessionId) else { return [] }
        let end = timing.endedAt ?? Date()
        guard timing.startedAt < end else { return [] }

        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: timing.startedAt, end: end, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let out: [HeartRateSamplePoint] = (samples as? [HKQuantitySample] ?? []).map { sample in
                    let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    return HeartRateSamplePoint(date: sample.startDate, bpm: bpm)
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    // MARK: - Private

    private func clearAttachment() {
        endMirroredWorkoutSessionIfNeeded()
        stopLiveEnergyPolling()
        workoutBuilder = nil
        attachedSessionId = nil
        sessionStart = nil
        heartAnchor = nil
        cumulativeActiveEnergyHealthKitKcal = nil
        healthKitWriter = .none
    }

    private func discardBuilderOnly() {
        workoutBuilder?.discardWorkout()
        workoutBuilder = nil
        healthKitWriter = .none
    }

    private func beginWorkoutBuilder(sessionStartedAt: Date) {
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let newBuilder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        workoutBuilder = newBuilder

        newBuilder.beginCollection(withStart: sessionStartedAt) { success, error in
            Task { @MainActor in
                if !success || error != nil {
                    newBuilder.discardWorkout()
                    if self.workoutBuilder === newBuilder {
                        self.workoutBuilder = nil
                    }
                }
            }
        }
    }

    private func finishBuilder(_ builder: HKWorkoutBuilder, start: Date, end: Date) async {
        let energy = Self.makeEstimatedActiveEnergySample(energyType: energyType, start: start, end: end)
        let storeRef = self.store
        let sessionIdRef = self.attachedSessionId
        let workoutsRef = self.workouts
        let finished: HKWorkout? = await withCheckedContinuation { (cont: CheckedContinuation<HKWorkout?, Never>) in
            builder.add([energy]) { _, _ in
                builder.endCollection(withEnd: end) { _, _ in
                    builder.finishWorkout { workout, _ in
                        cont.resume(returning: workout)
                    }
                }
            }
        }
        if let finished, let sessionIdRef {
            // Resolve session avg RPE on the main actor (DB access) and let HealthKit Training Load see this strength workout. Soft-fails on older OS / no-data.
            let avgRPE = (try? workoutsRef.sessionAverageRPE(sessionId: sessionIdRef)) ?? nil
            if let avgRPE {
                await AppleFitnessEffortRecorder.recordSessionEffort(
                    store: storeRef,
                    workout: finished,
                    sessionAverageRPE: avgRPE
                )
            }
        }
    }

    private func recordRetroactiveWorkout(startedAt: Date, endedAt: Date) async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        let energyQuantityType = energyType
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            builder.beginCollection(withStart: startedAt) { success, _ in
                guard success else {
                    builder.discardWorkout()
                    cont.resume()
                    return
                }
                let energy = Self.makeEstimatedActiveEnergySample(
                    energyType: energyQuantityType,
                    start: startedAt,
                    end: endedAt
                )
                builder.add([energy]) { _, _ in
                    builder.endCollection(withEnd: endedAt) { _, _ in
                        builder.finishWorkout { _, _ in
                            cont.resume()
                        }
                    }
                }
            }
        }
    }

    /// Rough Move-ring contribution for strength training (MET-based, default 75 kg). Apple Fitness may still adjust totals.
    /// `nonisolated` so `HKWorkoutBuilder` completion handlers can call it off the main actor.
    private nonisolated static func makeEstimatedActiveEnergySample(energyType: HKQuantityType, start: Date, end: Date) -> HKQuantitySample {
        let hours = max(end.timeIntervalSince(start) / 3600.0, 1.0 / 3600.0)
        let bodyMassKg = 75.0
        let met: Double = 5.0
        let kcalPerHour = (met * 3.5 * bodyMassKg) / 200.0 * 60.0
        let kcal = kcalPerHour * hours
        let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
        return HKQuantitySample(type: energyType, quantity: quantity, start: start, end: end)
    }

    private func startHeartRateQuery(from start: Date) {
        stopHeartRateQuery()

        // Avoid `.strictStartDate`: it can exclude samples whose start equals the workout start, so the first minutes look “empty”.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: heartAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            guard let self else { return }
            Task { @MainActor in
                self.heartAnchor = newAnchor
                self.applyHeartRateSamples(samples)
            }
        }

        query.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            guard let self else { return }
            Task { @MainActor in
                self.heartAnchor = newAnchor
                self.applyHeartRateSamples(samples)
            }
        }

        heartQuery = query
        store.execute(query)

        let observer = HKObserverQuery(sampleType: heartRateType, predicate: predicate) { [weak self] _, completionHandler, _ in
            guard let self else {
                completionHandler()
                return
            }
            Task { @MainActor in
                self.pollLatestHeartRateFromHealth {
                    completionHandler()
                }
            }
        }
        heartObserverQuery = observer
        store.execute(observer)

        heartRatePollTimer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.pollLatestHeartRateFromHealth(completion: nil)
                }
            }

        pollLatestHeartRateFromHealth(completion: nil)
    }

    /// Latest BPM at or after session start (cheap limit-1 query). Used by observer, poll, and cold start.
    private func pollLatestHeartRateFromHealth(completion: (() -> Void)?) {
        guard let start = sessionStart else {
            completion?()
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let sortEnd = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let sortStart = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let q = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: 1,
            sortDescriptors: [sortEnd, sortStart]
        ) { [weak self] _, samples, _ in
            defer { completion?() }
            guard let self, let sample = samples?.first as? HKQuantitySample else { return }
            let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            Task { @MainActor in
                guard sample.endDate >= self.lastAppliedHeartRateSampleEnd else { return }
                self.lastAppliedHeartRateSampleEnd = sample.endDate
                self.latestHeartRateBpm = Int(round(bpm))
            }
        }
        store.execute(q)
    }

    private func stopHeartRateQuery() {
        heartRatePollTimer?.cancel()
        heartRatePollTimer = nil
        if let heartObserverQuery {
            store.stop(heartObserverQuery)
        }
        heartObserverQuery = nil
        if let heartQuery {
            store.stop(heartQuery)
        }
        heartQuery = nil
        lastAppliedHeartRateSampleEnd = .distantPast
    }

    private func applyHeartRateSamples(_ samples: [HKSample]?) {
        guard let samples else { return }
        let quantities = samples.compactMap { $0 as? HKQuantitySample }
        guard let best = quantities.max(by: compareHeartRateSamplesByRecency) else { return }
        guard best.endDate >= lastAppliedHeartRateSampleEnd else { return }
        lastAppliedHeartRateSampleEnd = best.endDate
        let bpm = best.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        latestHeartRateBpm = Int(round(bpm))
    }

    private func compareHeartRateSamplesByRecency(_ a: HKQuantitySample, _ b: HKQuantitySample) -> Bool {
        if a.endDate != b.endDate { return a.endDate < b.endDate }
        return a.startDate < b.startDate
    }

    private func startLiveEnergyPolling() {
        stopLiveEnergyPolling()
        guard let start = sessionStart else { return }
        guard store.authorizationStatus(for: energyType) != .sharingDenied else { return }

        refreshCumulativeActiveEnergy(start: start)

        liveEnergyTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let s = self.sessionStart else { return }
                self.refreshCumulativeActiveEnergy(start: s)
            }
    }

    private func stopLiveEnergyPolling() {
        liveEnergyTimer?.cancel()
        liveEnergyTimer = nil
    }

    private func refreshCumulativeActiveEnergy(start: Date) {
        let end = Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsQuery(
            quantityType: energyType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, statistics, _ in
            guard let self else { return }
            let kcal = statistics?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie())
            Task { @MainActor in
                if let kcal, kcal > 0.05 {
                    self.cumulativeActiveEnergyHealthKitKcal = kcal
                } else {
                    self.cumulativeActiveEnergyHealthKitKcal = nil
                }
            }
        }
        store.execute(query)
    }

    /// Wakes the companion Watch app with the same strength-training configuration Loggy uses locally so ``WKApplicationDelegate`` can start the primary HK workout (Apple’s multi-device path).
    private func launchCompanionWatchAppViaHealthKit() async {
        guard isHealthDataAvailable else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            try await store.startWatchApp(toHandle: configuration)
        } catch {
            // Fall back to WC `prepareHK` only.
        }
    }

    private func retainMirroredWorkoutSession(_ session: HKWorkoutSession) {
        endMirroredWorkoutSessionIfNeeded()
        mirroredWorkoutSession = session
        session.delegate = mirroredWorkoutSessionDelegate
    }

    private func endMirroredWorkoutSessionIfNeeded() {
        guard let session = mirroredWorkoutSession else { return }
        switch session.state {
        case .running, .paused, .notStarted, .prepared:
            session.end()
        case .ended, .stopped:
            break
        @unknown default:
            session.end()
        }
        mirroredWorkoutSession = nil
    }
}

/// Minimal delegate so HealthKit keeps the mirrored ``HKWorkoutSession`` alive on iPhone.
private final class LoggyMirroredWorkoutSessionDelegate: NSObject, HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}
