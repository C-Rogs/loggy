import Foundation

/// Maps a [`ReadinessSnapshot`](ReadinessSnapshot) to advisory copy and glyphs (rules only, no ML).
public enum ReadinessEvaluator: Sendable {
    /// Minimum baseline HRV samples before ratio is trusted.
    public static let minimumBaselineHRVSamples = 5
    /// Short sleep threshold (hours).
    public static let shortSleepHours: Double = 5.0
    /// Comfortable sleep threshold (hours).
    public static let solidSleepHours: Double = 6.5
    /// HRV recent vs median baseline — below this suggests fatigue vs your norm.
    public static let hrvLowRatio: Double = 0.85
    /// Below this ratio vs baseline, treat HRV as clearly suppressed (stronger score penalty).
    public static let hrvVeryLowRatio: Double = 0.70

    public static func evaluate(_ s: ReadinessSnapshot) -> ReadinessInsight {
        let shortH = s.sleepShortThresholdHours ?? shortSleepHours
        let solidH = s.sleepSolidThresholdHours ?? solidSleepHours
        let lowR = s.hrvLowRatio ?? hrvLowRatio
        let veryLowR = s.hrvVeryLowRatio ?? hrvVeryLowRatio
        let personalized =
            s.usesPersonalSleepNorms || s.usesPersonalHRVNorms

        let sleepH = (s.sleepDurationSeconds ?? 0) / 3600.0
        let hasSleep = s.sleepDurationSeconds != nil && sleepH > 0.1
        let hrvTrust =
            s.hrvBaselineSampleCount >= minimumBaselineHRVSamples
            && s.hrvBaselineMedianMS != nil
            && s.hrvBaselineMedianMS! > 0
            && s.hrvRecentMS != nil

        var band: ReadinessBand = .unknown
        var headline = "Today’s readiness"
        var subline = "Based on Apple Health when sleep or HRV data is available."

        if !hasSleep, !hrvTrust {
            if !s.hadSleepAuthorization, !s.hadHRVAuthorization {
                subline = "Allow access to Sleep and Heart Rate Variability in Settings to see readiness."
            } else {
                subline = "No recent sleep or HRV in Health yet — Apple Watch helps fill this in."
            }
            return ReadinessInsight(
                band: .unknown,
                headline: headline,
                subline: subline,
                glyphPrimary: "moon.zzz",
                glyphCorners: ["heart.text.square", "moon.stars"],
                usesPersonalizedThresholds: false
            )
        }

        var score = 0.5
        if hasSleep {
            if sleepH >= solidH {
                score += 0.35
            } else if sleepH >= shortH {
                score += 0.2
            } else {
                score -= 0.25
            }
        }

        if hrvTrust, let recent = s.hrvRecentMS, let base = s.hrvBaselineMedianMS, base > 0 {
            let ratio = recent / base
            if ratio >= 1.0 {
                score += 0.15
            } else if ratio >= lowR {
                score += 0.05
            } else if ratio >= veryLowR {
                score -= 0.2
            } else {
                // Well below personal baseline — penalty large enough that solid sleep alone
                // does not mask a clearly suppressed HRV.
                score -= 0.45
            }
        }

        score = min(max(score, 0), 1)

        if score >= 0.72 {
            band = .high
            headline = "Well rested"
            subline = encouragementHigh(
                hasSleep: hasSleep,
                sleepH: sleepH,
                hrvTrust: hrvTrust,
                shortH: shortH,
                solidH: solidH,
                personalSleep: s.usesPersonalSleepNorms
            )
        } else if score >= 0.42 {
            band = .moderate
            headline = "Steady day"
            subline = encouragementModerate(
                hasSleep: hasSleep,
                sleepH: sleepH,
                hrvTrust: hrvTrust,
                shortH: shortH,
                lowR: lowR,
                veryLowR: veryLowR,
                s: s,
                personalSleep: s.usesPersonalSleepNorms
            )
        } else {
            band = .low
            headline = "Take it easier"
            subline = encouragementLow(
                hasSleep: hasSleep,
                sleepH: sleepH,
                hrvTrust: hrvTrust,
                shortH: shortH,
                lowR: lowR,
                s: s,
                personalSleep: s.usesPersonalSleepNorms
            )
        }

        let glyphs = glyphsFor(band: band, hasSleep: hasSleep, hrvTrust: hrvTrust)

        return ReadinessInsight(
            band: band,
            headline: headline,
            subline: subline,
            glyphPrimary: glyphs.primary,
            glyphCorners: glyphs.corners,
            usesPersonalizedThresholds: personalized
        )
    }

    private static func encouragementHigh(
        hasSleep: Bool,
        sleepH: Double,
        hrvTrust: Bool,
        shortH: Double,
        solidH: Double,
        personalSleep: Bool
    ) -> String {
        if hasSleep, sleepH >= solidH, hrvTrust {
            return personalSleep
                ? "Sleep looks typical or better for you and HRV is near your usual — a good day to push sets."
                : "Sleep looks solid and HRV is near your usual — a good day to push sets."
        }
        if hasSleep, sleepH >= solidH {
            return personalSleep
                ? "Sleep looks typical or better for you — good fuel for training today."
                : "Sleep looks solid — good fuel for training today."
        }
        if hrvTrust {
            return "HRV looks healthy vs your baseline — progress weight if form stays crisp."
        }
        return "Signals look favorable — train normally and listen to how sets feel."
    }

    private static func encouragementModerate(
        hasSleep: Bool,
        sleepH: Double,
        hrvTrust: Bool,
        shortH: Double,
        lowR: Double,
        veryLowR: Double,
        s: ReadinessSnapshot,
        personalSleep: Bool
    ) -> String {
        if hasSleep, sleepH < shortH {
            return personalSleep
                ? "Last night was shorter than your usual — consider lighter jumps between sets."
                : "Sleep was on the short side — consider lighter jumps between sets."
        }
        if hrvTrust, let r = s.hrvRecentMS, let b = s.hrvBaselineMedianMS, b > 0 {
            let ratio = r / b
            if ratio < lowR, ratio >= veryLowR {
                return "HRV is a bit below your usual — optional lighter accessories or fewer extras."
            }
        }
        return "Mixed signals — match effort to how warm-ups feel."
    }

    private static func encouragementLow(
        hasSleep: Bool,
        sleepH: Double,
        hrvTrust: Bool,
        shortH: Double,
        lowR: Double,
        s: ReadinessSnapshot,
        personalSleep: Bool
    ) -> String {
        if hasSleep, sleepH < shortH {
            return personalSleep
                ? "Last night was shorter than your usual — prioritize technique over PR chasing."
                : "Prior night sleep was short — prioritize technique over PR chasing."
        }
        if hrvTrust, let r = s.hrvRecentMS, let b = s.hrvBaselineMedianMS, b > 0, r / b < lowR {
            return "HRV is notably below baseline — favor recovery-friendly volume today."
        }
        return "Recovery signals are soft — keep intensity honest and leave a rep or two in reserve."
    }

    private static func glyphsFor(band: ReadinessBand, hasSleep: Bool, hrvTrust: Bool) -> (primary: String, corners: [String]) {
        let moon = hasSleep ? "moon.zzz.fill" : "moon.stars"
        let hrv = hrvTrust ? "waveform.path.ecg" : "heart.circle"
        switch band {
        case .high:
            return ("bolt.fill", [moon, hrv, "leaf.fill"])
        case .moderate:
            return ("figure.strengthtraining.traditional", [moon, hrv, "gauge.with.dots.needle.67percent"])
        case .low:
            return ("hare.fill", [moon, hrv, "cup.and.saucer.fill"])
        case .unknown:
            return ("moon.zzz", ["heart.text.square", "moon.stars"])
        }
    }
}
