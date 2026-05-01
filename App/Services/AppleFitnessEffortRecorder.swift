import Foundation
import HealthKit

/// Bridges Loggy's per-set RPE into the Apple Fitness Training Load picture by writing an `HKQuantitySample` of type `.workoutEffortScore` and relating it to the finished `HKWorkout` via `HKWorkoutEffortRelationship` on iOS 18+/watchOS 11+.
@MainActor
enum AppleFitnessEffortRecorder {
    /// Map a session's average RPE (1-10 scale) into the official `workoutEffortScore` quantity (also 1-10) and persist + relate it. Silently no-ops on older OSes or when HK is unavailable.
    static func recordSessionEffort(
        store: HKHealthStore,
        workout: HKWorkout,
        sessionAverageRPE: Double
    ) async {
        guard sessionAverageRPE > 0 else { return }
        // Workout effort score is 1…10 in HealthKit. Mirror our RPE 1…10 scale, clamped.
        let clamped = min(10, max(1, sessionAverageRPE))
        if #available(iOS 18.0, watchOS 11.0, *) {
            guard let effortType = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) else { return }
            let unit = HKUnit.appleEffortScore()
            let quantity = HKQuantity(unit: unit, doubleValue: clamped)
            let sample = HKQuantitySample(
                type: effortType,
                quantity: quantity,
                start: workout.startDate,
                end: workout.endDate
            )
            do {
                try await store.save(sample)
                try await store.relateWorkoutEffortSample(sample, with: workout, activity: nil)
            } catch {
                // Non-fatal: Training Load contribution simply won't include this workout. Log nothing — Apple's HK errors are noisy and the user can't act on them.
            }
        }
    }
}

@available(iOS 18.0, watchOS 11.0, *)
extension HKHealthStore {
    /// Wraps `relateWorkoutEffortSample` in async/throws since the public API is currently completion-handler based.
    func relateWorkoutEffortSample(_ sample: HKQuantitySample, with workout: HKWorkout, activity: HKWorkoutActivity?) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.relateWorkoutEffortSample(sample, with: workout, activity: activity) { _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }
}
