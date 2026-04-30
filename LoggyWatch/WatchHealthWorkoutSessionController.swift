import HealthKit
import Foundation

/// Owns the single HealthKit strength workout on Apple Watch (Option A) so heart rate streams reliably without duplicating the iPhone ``HKWorkoutBuilder`` session.
@MainActor
final class WatchHealthWorkoutSessionController: NSObject {
    private let store = HKHealthStore()
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var workoutSession: HKWorkoutSession?
    private var collectionStart: Date?
    /// Loggy session id bound to the running Watch HK session (for idempotent starts).
    private var activeLoggySessionId: String?

    private var pendingSessionStartDate: Date?
    private var pendingStartOutcomeContinuation: CheckedContinuation<Bool, Never>?
    private var didIssueStartActivityFromPreparedState = false
    private var didBeginCollectionForRunningState = false

    /// Forwards HR read from the live builder (throttled) — primary path for iPhone BPM vs HealthKit sync delay.
    var onLiveHeartRate: ((Int, Date) -> Void)?
    private var lastLiveHeartForwardAt: Date = .distantPast
    private let liveHeartForwardMinInterval: TimeInterval = 2.0

    private var lastStoreHeartFallbackAt: Date = .distantPast

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
        ]
        let read: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
        ]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
        } catch {}
    }

    /// True when this session id already has a live HK workout (HealthKit launch + WC handoff can both try to start).
    func isActiveForLoggySession(sessionId: String) -> Bool {
        activeLoggySessionId == sessionId && workoutSession != nil && workoutBuilder != nil
    }

    /// Starts collection for the Loggy session. Returns false if HealthKit refused or builder failed.
    /// Pass `workoutConfiguration` from ``WKApplicationDelegate/handle(_:)-1pfoc`` when HealthKit launches the Watch app so the session matches `startWatchApp(toHandle:)`.
    func start(sessionId: String, startedAt: Date, workoutConfiguration: HKWorkoutConfiguration? = nil) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        await requestAuthorization()
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return false }

        if activeLoggySessionId == sessionId, workoutSession != nil {
            return true
        }

        resetBeforeNewStart()

        let configuration = workoutConfiguration ?? Self.defaultStrengthConfiguration()
        if workoutConfiguration == nil {
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
        }

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            workoutSession = session
            workoutBuilder = builder
            collectionStart = startedAt
            activeLoggySessionId = sessionId
            session.delegate = self
            builder.delegate = self

            pendingSessionStartDate = startedAt
            didIssueStartActivityFromPreparedState = false
            didBeginCollectionForRunningState = false

            return await withCheckedContinuation { continuation in
                pendingStartOutcomeContinuation = continuation
                session.prepare()
            }
        } catch {
            activeLoggySessionId = nil
            resumePendingStartIfNeeded(success: false)
            return false
        }
    }

    private func resumePendingStartIfNeeded(success: Bool) {
        pendingStartOutcomeContinuation?.resume(returning: success)
        pendingStartOutcomeContinuation = nil
    }

    private static func defaultStrengthConfiguration() -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        return configuration
    }

    /// After ``HKHealthStore/startWatchApp(toHandle:)`` on iPhone, mirror state so the phone can attach to the same workout (WWDC multi-device flow).
    private func startMirroringToCompanionPhoneIfAvailable(_ session: HKWorkoutSession) async {
        do {
            try await session.startMirroringToCompanionDevice()
        } catch {
            // Non-fatal: HR can still stream on Watch; mirroring improves phone-side session continuity.
        }
    }

    func finish(endedAt: Date) async {
        guard let builder = workoutBuilder, let start = collectionStart else {
            tearDownAfterFinish()
            return
        }
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let energy = Self.makeEstimatedActiveEnergySample(energyType: energyType, start: start, end: endedAt)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            builder.add([energy]) { _, _ in
                builder.endCollection(withEnd: endedAt) { _, _ in
                    builder.finishWorkout { _, _ in
                        cont.resume()
                    }
                }
            }
        }
        tearDownAfterFinish()
    }

    func discard() {
        lastStoreHeartFallbackAt = .distantPast
        lastLiveHeartForwardAt = .distantPast
        resumePendingStartIfNeeded(success: false)
        workoutBuilder?.discardWorkout()
        endWorkoutSessionIfLive()
        workoutBuilder = nil
        workoutSession = nil
        collectionStart = nil
        activeLoggySessionId = nil
        clearPreparePipelineState()
    }

    /// Clears any prior Watch HK session before starting a new Loggy-linked workout.
    private func resetBeforeNewStart() {
        lastStoreHeartFallbackAt = .distantPast
        lastLiveHeartForwardAt = .distantPast
        resumePendingStartIfNeeded(success: false)
        workoutBuilder?.discardWorkout()
        endWorkoutSessionIfLive()
        workoutBuilder = nil
        workoutSession = nil
        collectionStart = nil
        activeLoggySessionId = nil
        clearPreparePipelineState()
    }

    private func clearPreparePipelineState() {
        pendingSessionStartDate = nil
        didIssueStartActivityFromPreparedState = false
        didBeginCollectionForRunningState = false
    }

    private func tearDownAfterFinish() {
        endWorkoutSessionIfLive()
        workoutBuilder = nil
        workoutSession = nil
        collectionStart = nil
        activeLoggySessionId = nil
        clearPreparePipelineState()
    }

    /// Ensures the running `HKWorkoutSession` is ended after discard or builder failure so sensors/session state don’t leak.
    private func endWorkoutSessionIfLive() {
        guard let session = workoutSession else { return }
        switch session.state {
        case .running, .paused, .notStarted, .prepared:
            session.end()
        case .ended, .stopped:
            break
        @unknown default:
            session.end()
        }
    }

    private nonisolated static func makeEstimatedActiveEnergySample(
        energyType: HKQuantityType,
        start: Date,
        end: Date
    ) -> HKQuantitySample {
        let hours = max(end.timeIntervalSince(start) / 3600.0, 1.0 / 3600.0)
        let bodyMassKg = 75.0
        let met: Double = 5.0
        let kcalPerHour = (met * 3.5 * bodyMassKg) / 200.0 * 60.0
        let kcal = kcalPerHour * hours
        let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
        return HKQuantitySample(type: energyType, quantity: quantity, start: start, end: end)
    }
}

extension WatchHealthWorkoutSessionController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            await self.handleWorkoutSessionStateChange(workoutSession: workoutSession, toState: toState)
        }
    }

    private func handleWorkoutSessionStateChange(workoutSession: HKWorkoutSession, toState: HKWorkoutSessionState) async {
        switch toState {
        case .prepared:
            guard !didIssueStartActivityFromPreparedState else { return }
            didIssueStartActivityFromPreparedState = true
            await startMirroringToCompanionPhoneIfAvailable(workoutSession)
            workoutSession.startActivity(with: pendingSessionStartDate ?? Date())
        case .running:
            guard !didBeginCollectionForRunningState else { return }
            guard let builder = workoutBuilder, let start = pendingSessionStartDate else {
                resumePendingStartIfNeeded(success: false)
                return
            }
            didBeginCollectionForRunningState = true
            builder.beginCollection(withStart: start) { success, _ in
                Task { @MainActor in
                    self.resumePendingStartIfNeeded(success: success)
                }
            }
        case .ended, .stopped:
            resumePendingStartIfNeeded(success: false)
        default:
            break
        }
    }

    nonisolated func workoutSession(_ session: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.resumePendingStartIfNeeded(success: false)
            self.workoutBuilder?.discardWorkout()
            self.endWorkoutSessionIfLive()
            self.workoutBuilder = nil
            self.workoutSession = nil
            self.collectionStart = nil
            self.activeLoggySessionId = nil
            self.clearPreparePipelineState()
        }
    }
}

extension WatchHealthWorkoutSessionController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(hrType)
        else { return }
        Task { @MainActor in
            if let quantity = workoutBuilder.statistics(for: hrType)?.mostRecentQuantity() {
                let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                let bpmInt = Int(round(bpm))
                guard (40 ..< 230).contains(bpmInt) else { return }
                let now = Date()
                guard now.timeIntervalSince(self.lastLiveHeartForwardAt) >= self.liveHeartForwardMinInterval else { return }
                self.lastLiveHeartForwardAt = now
                self.onLiveHeartRate?(bpmInt, now)
            } else {
                self.forwardLatestHeartRateFromHealthStore()
            }
        }
    }

    /// When builder statistics lag (early in session), still forward Watch HR that is already in HealthKit.
    private func forwardLatestHeartRateFromHealthStore() {
        guard Date().timeIntervalSince(lastStoreHeartFallbackAt) >= 3 else { return }
        lastStoreHeartFallbackAt = Date()
        let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let pred = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-300), end: Date(), options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            Task { @MainActor in
                guard let self, let s = samples?.first as? HKQuantitySample else { return }
                let bpm = Int(round(s.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))))
                guard (40 ..< 230).contains(bpm) else { return }
                guard Date().timeIntervalSince(self.lastLiveHeartForwardAt) >= self.liveHeartForwardMinInterval else { return }
                self.lastLiveHeartForwardAt = Date()
                self.onLiveHeartRate?(bpm, s.endDate)
            }
        }
        store.execute(q)
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
