import Combine
import Foundation
import HealthKit

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
    private var liveEnergyTimer: AnyCancellable?

    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!

    @Published private(set) var latestHeartRateBpm: Int?
    /// Merged HealthKit cumulative active energy for the current workout window (efficient 30s poll).
    @Published private(set) var cumulativeActiveEnergyHealthKitKcal: Double?
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
        startLiveEnergyPolling()
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
        stopHeartRateQuery()
        stopLiveEnergyPolling()
        workoutBuilder?.discardWorkout()
        clearAttachment()
    }

    /// Heart rate samples from Health for the session’s `started_at`…`ended_at` window (empty if unavailable or denied).
    func heartRateSamplesBpm(sessionId: String) async -> [HeartRateSamplePoint] {
        guard isHealthDataAvailable else { return [] }
        guard let timing = try? workouts.sessionHealthKitTiming(sessionId: sessionId) else { return [] }
        let end = timing.endedAt ?? Date()
        guard timing.startedAt < end else { return [] }
        guard store.authorizationStatus(for: heartRateType) == .sharingAuthorized else { return [] }

        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: timing.startedAt, end: end, options: .strictStartDate)
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
        stopLiveEnergyPolling()
        workoutBuilder = nil
        attachedSessionId = nil
        sessionStart = nil
        heartAnchor = nil
        cumulativeActiveEnergyHealthKitKcal = nil
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
        let energy = Self.makeEstimatedActiveEnergySample(energyType: energyType, start: start, end: end)
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
}
