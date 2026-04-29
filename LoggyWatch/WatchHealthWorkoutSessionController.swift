import HealthKit
import Foundation

/// Owns the single HealthKit strength workout on Apple Watch (Option A) so heart rate streams reliably without duplicating the iPhone ``HKWorkoutBuilder`` session.
@MainActor
final class WatchHealthWorkoutSessionController: NSObject {
    private let store = HKHealthStore()
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var workoutSession: HKWorkoutSession?
    private var collectionStart: Date?

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

    /// Starts collection for the Loggy session. Returns false if HealthKit refused or builder failed.
    func start(sessionId _: String, startedAt: Date) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        await requestAuthorization()
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return false }

        resetBeforeNewStart()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            workoutSession = session
            workoutBuilder = builder
            collectionStart = startedAt
            session.delegate = self
            builder.delegate = self

            session.prepare()
            session.startActivity(with: startedAt)

            return await withCheckedContinuation { continuation in
                builder.beginCollection(withStart: startedAt) { success, _ in
                    Task { @MainActor in
                        continuation.resume(returning: success)
                    }
                }
            }
        } catch {
            return false
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
        workoutBuilder?.discardWorkout()
        endWorkoutSessionIfLive()
        workoutBuilder = nil
        workoutSession = nil
        collectionStart = nil
    }

    /// Clears any prior Watch HK session before starting a new Loggy-linked workout.
    private func resetBeforeNewStart() {
        workoutBuilder?.discardWorkout()
        endWorkoutSessionIfLive()
        workoutBuilder = nil
        workoutSession = nil
        collectionStart = nil
    }

    private func tearDownAfterFinish() {
        endWorkoutSessionIfLive()
        workoutBuilder = nil
        workoutSession = nil
        collectionStart = nil
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
    ) {}

    nonisolated func workoutSession(_ session: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.workoutBuilder?.discardWorkout()
            self.endWorkoutSessionIfLive()
            self.workoutBuilder = nil
            self.workoutSession = nil
            self.collectionStart = nil
        }
    }
}

extension WatchHealthWorkoutSessionController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
