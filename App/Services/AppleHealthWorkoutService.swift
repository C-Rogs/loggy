import Combine
import Foundation
import HealthKit

/// Bridges active Loggy sessions to Apple Health: traditional strength `HKWorkout` (Exercise ring / Fitness),
/// estimated active energy (Move ring), and live heart rate from whatever writes HR to HealthKit (usually Apple Watch).
/// Consumer AirPods do not expose heart rate to HealthKit.
@MainActor
final class AppleHealthWorkoutService: ObservableObject {
    static let syncEnabledKey = "loggyAppleHealthWorkoutSync"

    private let store = HKHealthStore()
    private let workouts: WorkoutSessionRepository

    private var workoutBuilder: HKWorkoutBuilder?
    private var attachedSessionId: String?
    private var sessionStart: Date?
    private var heartAnchor: HKQueryAnchor?
    private var heartQuery: HKAnchoredObjectQuery?

    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!

    @Published private(set) var latestHeartRateBpm: Int?
    @Published private(set) var isHealthDataAvailable: Bool
    @Published private(set) var syncWorkoutsToHealthEnabled: Bool

    init(workouts: WorkoutSessionRepository) {
        self.workouts = workouts
        isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()
        syncWorkoutsToHealthEnabled = UserDefaults.standard.object(forKey: Self.syncEnabledKey) as? Bool ?? false
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
            latestHeartRateBpm = nil
        }
    }

    func requestAuthorization() async {
        guard isHealthDataAvailable else { return }
        let toShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            energyType,
        ]
        let toRead: Set<HKObjectType> = [heartRateType]
        do {
            try await store.requestAuthorization(toShare: toShare, read: toRead)
        } catch {
            // Denied or restricted; user can retry from Settings.
        }
    }

    func activeWorkoutScreenAppeared(sessionId: String, sessionStartedAt: Date) {
        guard isHealthDataAvailable, syncWorkoutsToHealthEnabled else { return }

        if attachedSessionId != sessionId {
            discardBuilderOnly()
            stopHeartRateQuery()
            attachedSessionId = sessionId
            sessionStart = sessionStartedAt
            beginWorkoutBuilder(sessionStartedAt: sessionStartedAt)
        } else if sessionStart != sessionStartedAt {
            sessionStart = sessionStartedAt
        }

        startHeartRateQuery(from: sessionStartedAt)
    }

    func activeWorkoutScreenDisappeared() {
        stopHeartRateQuery()
    }

    /// Call after `finishSession` succeeds so `ended_at` exists for the retroactive path.
    func onWorkoutFinished(sessionId: String) async {
        guard isHealthDataAvailable, syncWorkoutsToHealthEnabled else { return }
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }

        if attachedSessionId == sessionId, let builder = workoutBuilder, let start = sessionStart {
            stopHeartRateQuery()
            let end = Date()
            await finishBuilder(builder, start: start, end: end)
            clearAttachment()
            return
        }

        guard let timing = try? workouts.sessionHealthKitTiming(sessionId: sessionId),
              let ended = timing.endedAt
        else { return }
        await recordRetroactiveWorkout(startedAt: timing.startedAt, endedAt: ended)
    }

    func onWorkoutDiscarded(sessionId: String) {
        guard attachedSessionId == sessionId else { return }
        stopHeartRateQuery()
        workoutBuilder?.discardWorkout()
        clearAttachment()
    }

    // MARK: - Private

    private func clearAttachment() {
        workoutBuilder = nil
        attachedSessionId = nil
        sessionStart = nil
        heartAnchor = nil
    }

    private func discardBuilderOnly() {
        workoutBuilder?.discardWorkout()
        workoutBuilder = nil
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
        let energy = estimatedActiveEnergySample(start: start, end: end)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            builder.add([energy]) { _, _ in
                builder.endCollection(withEnd: end) { _, _ in
                    builder.finishWorkout { _, _ in
                        cont.resume()
                    }
                }
            }
        }
    }

    private func recordRetroactiveWorkout(startedAt: Date, endedAt: Date) async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            builder.beginCollection(withStart: startedAt) { success, _ in
                guard success else {
                    builder.discardWorkout()
                    cont.resume()
                    return
                }
                let energy = self.estimatedActiveEnergySample(start: startedAt, end: endedAt)
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
    private func estimatedActiveEnergySample(start: Date, end: Date) -> HKQuantitySample {
        let hours = max(end.timeIntervalSince(start) / 3600.0, 1.0 / 3600.0)
        let bodyMassKg = 75.0
        let met: Double = 5.0
        let kcalPerHour = (met * 3.5 * bodyMassKg) / 200.0 * 60.0
        let kcal = kcalPerHour * hours
        let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
        return HKQuantitySample(type: energyType, quantity: quantity, start: start, end: end)
    }

    private func startHeartRateQuery(from start: Date) {
        guard store.authorizationStatus(for: heartRateType) != .sharingDenied else { return }

        stopHeartRateQuery()

        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)

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
    }

    private func stopHeartRateQuery() {
        if let heartQuery {
            store.stop(heartQuery)
        }
        heartQuery = nil
    }

    private func applyHeartRateSamples(_ samples: [HKSample]?) {
        guard let samples else { return }
        for s in samples {
            guard let q = s as? HKQuantitySample else { continue }
            let bpm = q.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            latestHeartRateBpm = Int(round(bpm))
        }
    }
}
