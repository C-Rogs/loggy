import Foundation
import HealthKit

/// Optional Apple Health reads for **daily context** (steps, cardio fitness) separate from live workout HR.
/// Used for coaching / future energy-budget surfaces — never canonical workout truth.
@MainActor
public final class HealthKitDailySignalsService: ObservableObject {
    private let store = HKHealthStore()

    public init() {}

    /// Steps counted so far today (midnight → now). `nil` when Health unavailable or query empty / denied.
    public func fetchStepCountToday(now: Date = Date()) async -> Int? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }

        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let n = statistics?.sumQuantity()?.doubleValue(for: HKUnit.count())
                continuation.resume(returning: n.map { Int($0.rounded()) })
            }
            store.execute(query)
        }
    }

    /// Latest VO₂ max estimate (ml/kg/min) when Apple has recorded one. Mostly from outdoor cardio — sparse for strength-only users.
    public func fetchLatestVO2Max() async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        guard let vo2Type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return nil }

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: vo2Type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let s = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let mlkgmin = HKUnit.literUnit(with: .milli)
                    .unitDivided(by: HKUnit.gramUnit(with: .kilo))
                    .unitDivided(by: HKUnit.minute())
                let v = s.quantity.doubleValue(for: mlkgmin)
                continuation.resume(returning: v > 0 ? v : nil)
            }
            store.execute(query)
        }
    }

    /// Request read access for auxiliary types (safe to call repeatedly). Does not replace workout/recovery flows.
    public func requestAuxiliaryReadAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount),
              let vo2Type = HKQuantityType.quantityType(forIdentifier: .vo2Max)
        else { return }
        let read: Set<HKObjectType> = [stepType, vo2Type]
        do {
            try await store.requestAuthorization(toShare: [], read: read)
        } catch {
            // Denied — callers continue with nil signals.
        }
    }
}
