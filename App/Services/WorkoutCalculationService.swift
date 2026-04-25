import Foundation

/// Stub for future estimated 1RM / volume rules beyond SQL caches.
enum WorkoutCalculationService {
    static func estimatedOneRM(weightKg: Double, reps: Int) -> Double {
        guard weightKg > 0, reps > 0 else { return 0 }
        // Epley
        return weightKg * (1 + Double(reps) / 30.0)
    }
}
