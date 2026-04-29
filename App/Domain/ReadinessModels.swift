import Foundation

/// Discrete readiness level from rules + Apple Health signals (advisory only).
public enum ReadinessBand: String, Sendable, Equatable, CaseIterable {
    case high
    case moderate
    case low
    case unknown
}

/// Raw metrics from HealthKit before rule evaluation.
public struct ReadinessSnapshot: Sendable, Equatable {
    /// Sum of asleep segments in the query window (typically last main sleep period).
    public var sleepDurationSeconds: TimeInterval?
    /// Most recent HRV SDNN in the lookback window (ms).
    public var hrvRecentMS: Double?
    /// Median HRV SDNN over baseline window (ms).
    public var hrvBaselineMedianMS: Double?
    public var hrvBaselineSampleCount: Int
    public var hadSleepAuthorization: Bool
    public var hadHRVAuthorization: Bool
    /// Below this duration (hours), sleep counts as “short” — from [`ReadinessNormsStore`] when enough history exists.
    public var sleepShortThresholdHours: Double?
    /// At or above counts as “solid” sleep for scoring — personalized after several logged mornings.
    public var sleepSolidThresholdHours: Double?
    /// Optional overrides for HRV ratio tiers (`recent/baseline`), derived from this user’s ratio history.
    public var hrvLowRatio: Double?
    public var hrvVeryLowRatio: Double?
    public var usesPersonalSleepNorms: Bool
    public var usesPersonalHRVNorms: Bool

    public init(
        sleepDurationSeconds: TimeInterval? = nil,
        hrvRecentMS: Double? = nil,
        hrvBaselineMedianMS: Double? = nil,
        hrvBaselineSampleCount: Int = 0,
        hadSleepAuthorization: Bool = false,
        hadHRVAuthorization: Bool = false,
        sleepShortThresholdHours: Double? = nil,
        sleepSolidThresholdHours: Double? = nil,
        hrvLowRatio: Double? = nil,
        hrvVeryLowRatio: Double? = nil,
        usesPersonalSleepNorms: Bool = false,
        usesPersonalHRVNorms: Bool = false
    ) {
        self.sleepDurationSeconds = sleepDurationSeconds
        self.hrvRecentMS = hrvRecentMS
        self.hrvBaselineMedianMS = hrvBaselineMedianMS
        self.hrvBaselineSampleCount = hrvBaselineSampleCount
        self.hadSleepAuthorization = hadSleepAuthorization
        self.hadHRVAuthorization = hadHRVAuthorization
        self.sleepShortThresholdHours = sleepShortThresholdHours
        self.sleepSolidThresholdHours = sleepSolidThresholdHours
        self.hrvLowRatio = hrvLowRatio
        self.hrvVeryLowRatio = hrvVeryLowRatio
        self.usesPersonalSleepNorms = usesPersonalSleepNorms
        self.usesPersonalHRVNorms = usesPersonalHRVNorms
    }
}

/// User-facing coaching copy and SF Symbol names for the readiness UI.
public struct ReadinessInsight: Sendable, Equatable {
    public var band: ReadinessBand
    public var headline: String
    public var subline: String
    /// Primary animated glyph (e.g. bolt, leaf).
    public var glyphPrimary: String
    /// Decorative corner glyphs (sleep, HRV, mood).
    public var glyphCorners: [String]
    /// True when sleep and/or HRV tier boundaries use locally learned norms, not population defaults.
    public var usesPersonalizedThresholds: Bool

    public init(
        band: ReadinessBand,
        headline: String,
        subline: String,
        glyphPrimary: String,
        glyphCorners: [String],
        usesPersonalizedThresholds: Bool = false
    ) {
        self.band = band
        self.headline = headline
        self.subline = subline
        self.glyphPrimary = glyphPrimary
        self.glyphCorners = glyphCorners
        self.usesPersonalizedThresholds = usesPersonalizedThresholds
    }
}
