import Foundation

/// Persists per-user readiness calibration from Apple Health queries (advisory only; not workout truth).
enum ReadinessNormsStore {
    static let userDefaultsKey = "loggyReadinessNorms.v1"

    struct Persisted: Codable, Equatable {
        /// Local-calendar day key (`yyyy-MM-dd`) → prior-night sleep hours attributed to that morning.
        var sleepHoursByDayKey: [String: Double] = [:]
        /// Day key → recent HRV / baseline median ratio when baseline was trusted.
        var hrvRatioByDayKey: [String: Double] = [:]
    }

    static func load() -> Persisted {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return Persisted()
        }
        do {
            return try JSONDecoder().decode(Persisted.self, from: data)
        } catch {
            return Persisted()
        }
    }

    static func save(_ p: Persisted) {
        do {
            let data = try JSONEncoder().encode(p)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            // Ignore persistence failure; readiness still works with population defaults.
        }
    }

    /// Minimum recorded mornings before sleep thresholds personalize.
    static let minimumSleepSamplesForPersonalization = 7
    /// Minimum ratio samples before HRV tier boundaries personalize.
    static let minimumHRVSamplesForPersonalization = 10
    static let maxStoredDays = 28

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.startOfDay(for: date)
        let y = calendar.component(.year, from: c)
        let m = calendar.component(.month, from: c)
        let d = calendar.component(.day, from: c)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func mergeSleepSample(into persisted: inout Persisted, dayKey: String, hours: Double) {
        guard hours >= 2, hours <= 14 else { return }
        persisted.sleepHoursByDayKey[dayKey] = hours
        trimMap(&persisted.sleepHoursByDayKey, maxKeys: maxStoredDays)
    }

    static func mergeHRVRatioSample(into persisted: inout Persisted, dayKey: String, ratio: Double) {
        guard ratio > 0.25, ratio < 4.0, ratio.isFinite else { return }
        persisted.hrvRatioByDayKey[dayKey] = ratio
        trimMap(&persisted.hrvRatioByDayKey, maxKeys: maxStoredDays)
    }

    private static func trimMap(_ map: inout [String: Double], maxKeys: Int) {
        guard map.count > maxKeys else { return }
        let sortedKeys = map.keys.sorted()
        let drop = map.count - maxKeys
        if drop > 0 {
            for k in sortedKeys.prefix(drop) {
                map.removeValue(forKey: k)
            }
        }
    }

    /// Sleep buckets from this user’s recent nights; `nil` until enough history.
    static func personalSleepThresholds(from persisted: Persisted) -> (short: Double, solid: Double)? {
        let hours = persisted.sleepHoursByDayKey.values.map(\.self)
        guard hours.count >= minimumSleepSamplesForPersonalization else { return nil }
        guard let m = median(hours), m > 0 else { return nil }
        // Solid = near this user’s typical night; short = clearly below their median (not population 6.5h).
        let solid = min(max(m * 0.94, 4.2), 11.0)
        let rawShort = min(m * 0.82, m - 1.15)
        let short = max(3.25, min(rawShort, solid - 0.65))
        guard short + 0.35 < solid else { return nil }
        return (short, solid)
    }

    /// HRV tier boundaries from distribution of this user’s recent vs baseline ratios.
    static func personalHRVThresholds(from persisted: Persisted) -> (low: Double, veryLow: Double)? {
        let ratios = persisted.hrvRatioByDayKey.values.map(\.self)
        guard ratios.count >= minimumHRVSamplesForPersonalization else { return nil }
        let sorted = ratios.sorted()
        guard let p30 = percentile(sorted, 0.30), let p12 = percentile(sorted, 0.12) else { return nil }
        // Below typical spread → mild concern; far below → stronger signal.
        let low = min(0.90, max(0.76, p30 + 0.02))
        var veryLow = min(low - 0.12, p12)
        veryLow = max(0.52, min(veryLow, low - 0.06))
        guard veryLow < low else { return nil }
        return (low, veryLow)
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

    private static func percentile(_ sortedAscending: [Double], _ p: Double) -> Double? {
        guard !sortedAscending.isEmpty, p >= 0, p <= 1 else { return nil }
        if sortedAscending.count == 1 { return sortedAscending[0] }
        let idx = Double(sortedAscending.count - 1) * p
        let lo = Int(floor(idx))
        let hi = Int(ceil(idx))
        if lo == hi { return sortedAscending[lo] }
        let f = idx - Double(lo)
        return sortedAscending[lo] * (1 - f) + sortedAscending[hi] * f
    }
}
