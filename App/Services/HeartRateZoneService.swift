import Foundation
import HealthKit

/// Heart-rate-reserve (HRR) zones used by the IntraSessionCoach.
///
/// HRR = (HRcurrent - HRrest) / (HRmax - HRrest)
///
/// Bins follow the common 5-zone model used by Garmin / Apple Fitness+ briefings:
/// Z1 < 60 %, Z2 60-70 %, Z3 70-80 %, Z4 80-90 %, Z5 ≥ 90 %.
public enum HeartRateZone: Int, Codable, Sendable, CaseIterable, Comparable {
    case z1 = 1
    case z2 = 2
    case z3 = 3
    case z4 = 4
    case z5 = 5

    public static func < (lhs: HeartRateZone, rhs: HeartRateZone) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .z1: return "Z1"
        case .z2: return "Z2"
        case .z3: return "Z3"
        case .z4: return "Z4"
        case .z5: return "Z5"
        }
    }

    /// Lower-bound HRR fraction used when computing zone for a BPM.
    fileprivate static func zone(forFraction f: Double) -> HeartRateZone {
        switch f {
        case ..<0.60: return .z1
        case ..<0.70: return .z2
        case ..<0.80: return .z3
        case ..<0.90: return .z4
        default: return .z5
        }
    }
}

/// Inputs to the HRR calculation. The service can be constructed pure-functionally for tests, or via Apple Health for runtime.
public struct HeartRateProfile: Equatable, Sendable {
    /// Estimated max HR (bpm). When the user supplies DOB we use 220 - age; can be overridden if the user logs a true tested max.
    public var maxBpm: Double
    /// Resting HR baseline (bpm). Latest Apple Health resting sample within ~7 days is preferred.
    public var restBpm: Double

    public init(maxBpm: Double, restBpm: Double) {
        self.maxBpm = maxBpm
        self.restBpm = restBpm
    }

    public var hrr: Double { max(0, maxBpm - restBpm) }
}

/// Pure logic — separated from the HealthKit layer so it can be unit-tested without an HK store. Reuses the existing ``HeartRateSamplePoint`` defined in `AppleHealthWorkoutService` for set-window aggregation.
public enum HeartRateZoneMath {
    /// HRR fraction (0…1), clamped. Returns `nil` if the profile has no useful range (e.g. rest >= max).
    public static func hrrFraction(bpm: Int, profile: HeartRateProfile) -> Double? {
        let denom = profile.hrr
        guard denom > 0 else { return nil }
        let raw = (Double(bpm) - profile.restBpm) / denom
        return min(max(raw, 0), 1)
    }

    public static func zone(bpm: Int, profile: HeartRateProfile) -> HeartRateZone? {
        guard let f = hrrFraction(bpm: bpm, profile: profile) else { return nil }
        return HeartRateZone.zone(forFraction: f)
    }

    /// Mean HRR fraction across a sample window (e.g. start-of-set ... end-of-set). Returns `nil` when no samples or no usable range.
    public static func effortScore(samples: [HeartRateSamplePoint], profile: HeartRateProfile) -> Double? {
        guard !samples.isEmpty else { return nil }
        let fractions = samples.compactMap { hrrFraction(bpm: Int($0.bpm.rounded()), profile: profile) }
        guard !fractions.isEmpty else { return nil }
        return fractions.reduce(0, +) / Double(fractions.count)
    }

    /// Default max HR estimate. Fox & Haskell formula; good enough for relative zone assignment per Apple Fitness docs.
    public static func defaultMaxBpm(forAgeYears age: Int) -> Double {
        max(120, Double(220 - age))
    }
}

/// Reads the user's date of birth and resting heart rate from HealthKit so we can compute live zones for the IntraSessionCoach.
@MainActor
final class HeartRateZoneService: ObservableObject {
    static let shared = HeartRateZoneService()

    private let store = HKHealthStore()
    /// Cache of the last successfully computed profile so callers can render zones synchronously.
    @Published private(set) var profile: HeartRateProfile?

    private var lastRefreshAt: Date?
    private let refreshInterval: TimeInterval = 6 * 3600

    func zone(forBpm bpm: Int) -> HeartRateZone? {
        guard let p = profile else { return nil }
        return HeartRateZoneMath.zone(bpm: bpm, profile: p)
    }

    func hrrFraction(forBpm bpm: Int) -> Double? {
        guard let p = profile else { return nil }
        return HeartRateZoneMath.hrrFraction(bpm: bpm, profile: p)
    }

    /// Refresh from HealthKit if the cached profile is stale. Silently no-ops when Health is unavailable; UI then renders without zone tinting.
    func refreshIfNeeded() async {
        if let last = lastRefreshAt, Date().timeIntervalSince(last) < refreshInterval { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let dobComponents = try? store.dateOfBirthComponents()
        let resting = await fetchRestingBpm()
        let age: Int
        if let dobComponents {
            age = Int(Self.years(from: dobComponents, to: Date()))
        } else {
            age = 30
        }
        let maxBpm = HeartRateZoneMath.defaultMaxBpm(forAgeYears: age)
        let resolvedRest = resting ?? 60
        profile = HeartRateProfile(maxBpm: maxBpm, restBpm: resolvedRest)
        lastRefreshAt = Date()
    }

    private func fetchRestingBpm() async -> Double? {
        let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: weekAgo, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                guard let s = samples?.first as? HKQuantitySample else {
                    cont.resume(returning: nil)
                    return
                }
                let bpm = s.quantity.doubleValue(for: HKUnit(from: "count/min"))
                cont.resume(returning: bpm)
            }
            store.execute(q)
        }
    }

    private static func years(from dob: DateComponents, to now: Date) -> Double {
        guard let date = Calendar(identifier: .gregorian).date(from: dob) else { return 30 }
        let interval = now.timeIntervalSince(date)
        return interval / (365.25 * 24 * 3600)
    }
}
