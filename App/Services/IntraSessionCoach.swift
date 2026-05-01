import Foundation

/// User-facing intensity preference. Drives the IntraSessionCoach's target HR zone for the live "push harder / coast / cool down" advisory engine.
public enum CoachIntensity: String, CaseIterable, Identifiable, Codable, Sendable {
    case off, light, standard, aggressive

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: return "Off"
        case .light: return "Light"
        case .standard: return "Standard"
        case .aggressive: return "Aggressive"
        }
    }

    /// Lower bound HR zone the coach wants to nudge the user toward. `Off` returns nil.
    public var targetZone: HeartRateZone? {
        switch self {
        case .off: return nil
        case .light: return .z2
        case .standard: return .z3
        case .aggressive: return .z4
        }
    }
}

/// Result of a single rules-driven advisory pass — kept tiny so it can be rendered in the rest banner or a Live Activity slot.
public struct CoachAdvisory: Equatable, Sendable {
    public enum Tone: Sendable { case neutral, push, taper, recover }
    public let headline: String
    public let detail: String?
    public let tone: Tone

    public init(headline: String, detail: String? = nil, tone: Tone) {
        self.headline = headline
        self.detail = detail
        self.tone = tone
    }
}

/// Inputs surfaced to the coach after a set completes. All fields are optional so the coach degrades gracefully when HR / HRV is unavailable.
public struct IntraSessionCoachInput: Sendable {
    public var lastSetEffort: Double?
    public var lastSetZone: HeartRateZone?
    public var intensity: CoachIntensity
    public var hrvLowVsBaseline: Bool

    public init(
        lastSetEffort: Double?,
        lastSetZone: HeartRateZone?,
        intensity: CoachIntensity,
        hrvLowVsBaseline: Bool
    ) {
        self.lastSetEffort = lastSetEffort
        self.lastSetZone = lastSetZone
        self.intensity = intensity
        self.hrvLowVsBaseline = hrvLowVsBaseline
    }
}

/// Pure rules-engine — per project rules: rules first, LLM text only for embellishment.
public enum IntraSessionCoach {
    public static func evaluate(_ input: IntraSessionCoachInput) -> CoachAdvisory? {
        guard let target = input.intensity.targetZone else { return nil }

        // HRV gate: if user is under-recovered, never push harder.
        if input.hrvLowVsBaseline {
            return CoachAdvisory(
                headline: "HRV is low today",
                detail: "Consider lighter sets or longer rest.",
                tone: .recover
            )
        }

        guard let zone = input.lastSetZone else {
            return nil
        }

        if zone < target {
            return CoachAdvisory(
                headline: "HR was \(zone.label) — push 1-2 more reps next set",
                detail: "Target is \(target.label).",
                tone: .push
            )
        } else if zone == target {
            return CoachAdvisory(
                headline: "On target (\(zone.label))",
                tone: .neutral
            )
        } else {
            return CoachAdvisory(
                headline: "Already \(zone.label) — you're cooking",
                detail: "Recover, then keep going.",
                tone: .taper
            )
        }
    }
}

/// `UserDefaults` shim for the user-facing intensity setting. Kept tiny so it can be observed by SwiftUI via a `@Published` proxy in HomeView later.
public enum CoachIntensityStore {
    private static let defaultsName = "loggy_coach_intensity_pref"

    public static func load() -> CoachIntensity {
        if let raw = UserDefaults.standard.string(forKey: defaultsName),
           let v = CoachIntensity(rawValue: raw) {
            return v
        }
        return .standard
    }

    public static func save(_ value: CoachIntensity) {
        UserDefaults.standard.set(value.rawValue, forKey: defaultsName)
    }
}
