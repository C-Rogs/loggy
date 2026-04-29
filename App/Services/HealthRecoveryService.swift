import Foundation
import HealthKit

/// Reads sleep and HRV SDNN from HealthKit for advisory readiness (separate from live workout HR sync).
@MainActor
final class HealthRecoveryService: ObservableObject {
    static let recoveryInsightsEnabledKey = "loggyRecoveryInsightsEnabled"

    private let store = HKHealthStore()

    private var sleepType: HKCategoryType { HKObjectType.categoryType(forIdentifier: .sleepAnalysis)! }
    private var hrvType: HKQuantityType { HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)! }
    private let hrvMilliUnit = HKUnit.secondUnit(with: .milli)

    @Published private(set) var recoveryInsightsEnabled: Bool
    @Published private(set) var isHealthDataAvailable: Bool

    init() {
        isHealthDataAvailable = HKHealthStore.isHealthDataAvailable()
        recoveryInsightsEnabled = UserDefaults.standard.object(forKey: Self.recoveryInsightsEnabledKey) as? Bool ?? false
    }

    func setRecoveryInsightsEnabled(_ enabled: Bool) {
        guard enabled != recoveryInsightsEnabled else { return }
        recoveryInsightsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.recoveryInsightsEnabledKey)
        if enabled {
            Task { await requestAuthorization() }
        }
    }

    /// Read-only authorization for sleep + HRV (independent of workout write/sync).
    func requestAuthorization() async {
        guard isHealthDataAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [sleepType, hrvType])
        } catch {
            // User denied or restricted.
        }
    }

    func fetchReadinessInsight() async -> ReadinessInsight? {
        guard recoveryInsightsEnabled, isHealthDataAvailable else { return nil }
        let snapshot = await fetchSnapshot()
        return ReadinessEvaluator.evaluate(snapshot)
    }

    func fetchSnapshot() async -> ReadinessSnapshot {
        guard isHealthDataAvailable else {
            return ReadinessSnapshot(hadSleepAuthorization: false, hadHRVAuthorization: false)
        }

        let sleepAuth = authorizationAllowed(for: sleepType)
        let hrvAuth = authorizationAllowed(for: hrvType)

        let now = Date()
        let dayKey = ReadinessNormsStore.dayKey(for: now)
        let sleepWindowStart = now.addingTimeInterval(-40 * 3600)

        let sleepSeconds: TimeInterval? =
            sleepAuth
            ? await sumSleepAsleepSeconds(from: sleepWindowStart, to: now)
            : nil

        let baselineStart = now.addingTimeInterval(-14 * 24 * 3600)
        let baselineEnd = now.addingTimeInterval(-36 * 3600)

        let baselineSamples: [Double] =
            hrvAuth
            ? await fetchHRVSamples(from: baselineStart, to: baselineEnd)
            : []

        let recentSamples: [Double] =
            hrvAuth
            ? await fetchHRVSamples(from: now.addingTimeInterval(-36 * 3600), to: now)
            : []

        let median = Self.median(baselineSamples)
        let recent = recentSamples.last

        var norms = ReadinessNormsStore.load()
        if let sec = sleepSeconds, sleepAuth {
            ReadinessNormsStore.mergeSleepSample(
                into: &norms,
                dayKey: dayKey,
                hours: sec / 3600.0
            )
        }
        if let recent, let med = median, med > 0, hrvAuth {
            ReadinessNormsStore.mergeHRVRatioSample(
                into: &norms,
                dayKey: dayKey,
                ratio: recent / med
            )
        }
        ReadinessNormsStore.save(norms)

        let sleepPersonal = ReadinessNormsStore.personalSleepThresholds(from: norms)
        let hrvPersonal = ReadinessNormsStore.personalHRVThresholds(from: norms)

        return ReadinessSnapshot(
            sleepDurationSeconds: sleepSeconds,
            hrvRecentMS: recent,
            hrvBaselineMedianMS: median,
            hrvBaselineSampleCount: baselineSamples.count,
            hadSleepAuthorization: sleepAuth,
            hadHRVAuthorization: hrvAuth,
            sleepShortThresholdHours: sleepPersonal?.short,
            sleepSolidThresholdHours: sleepPersonal?.solid,
            hrvLowRatio: hrvPersonal?.low,
            hrvVeryLowRatio: hrvPersonal?.veryLow,
            usesPersonalSleepNorms: sleepPersonal != nil,
            usesPersonalHRVNorms: hrvPersonal != nil
        )
    }

    // MARK: - Private

    private func authorizationAllowed(for type: HKObjectType) -> Bool {
        let s = store.authorizationStatus(for: type)
        return s == .sharingAuthorized
    }

    private func sumSleepAsleepSeconds(from start: Date, to end: Date) async -> TimeInterval {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let cats = (samples as? [HKCategorySample]) ?? []
                var total: TimeInterval = 0
                for s in cats where Self.isAsleepSleepSample(s) {
                    total += s.endDate.timeIntervalSince(s.startDate)
                }
                continuation.resume(returning: total)
            }
            store.execute(query)
        }
    }

    private nonisolated static func isAsleepSleepSample(_ sample: HKCategorySample) -> Bool {
        guard let v = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return false }
        switch v {
        case .asleep, .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
            return true
        case .inBed, .awake:
            return false
        @unknown default:
            return false
        }
    }

    private func fetchHRVSamples(from start: Date, to end: Date) async -> [Double] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let qs = (samples as? [HKQuantitySample]) ?? []
                let values = qs.map { $0.quantity.doubleValue(for: self.hrvMilliUnit) }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let m = s.count / 2
        if s.count % 2 == 0 {
            return (s[m - 1] + s[m]) / 2
        }
        return s[m]
    }
}
