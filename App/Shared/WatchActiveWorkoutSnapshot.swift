import Foundation

/// Payload mirrored to Apple Watch via Watch Connectivity (ISO 8601 UTC strings per persistence rules).
public struct WatchActiveWorkoutSnapshot: Codable, Equatable, Sendable {
    /// Bump when adding breaking WC fields so older Watch builds can degrade gracefully.
    public static let currentWatchConnectivitySchemaVersion: Int = 4

    public enum Phase: String, Codable, Sendable {
        case idle
        case active
        case ending
    }

    /// Protocol version for Watch ↔ iPhone snapshot JSON (decode defaults to `1` when omitted).
    public var watchConnectivitySchemaVersion: Int
    public var sessionId: String
    /// UTC ISO8601
    public var workoutStartedAt: String?
    public var phase: Phase
    public var currentExerciseName: String
    public var completedSetCount: Int
    /// UTC ISO8601 when rest is active
    public var restEndsAt: String?
    public var restStartedAt: String?
    /// When true, Watch may own the HealthKit workout session for reliable HR (Option A).
    public var healthSyncEnabled: Bool
    /// `true` = iPhone chose Watch as the sole ``HKLiveWorkoutSession`` writer; `false` = iPhone owns HK; `nil` = still negotiating — Watch must **not** start a Watch HK session until `true`.
    public var watchRunsHealthKitSession: Bool?

    /// Title for the next set the user should perform (e.g. `"Set 2"` / `"W"`).
    public var currentSetTitle: String
    /// Display string for the next set's weight (e.g. `"40.0"`, `"—"`, or `"2.50 km"`).
    public var currentSetWeightDisplay: String
    /// Display string for the next set's reps / duration (e.g. `"8"`, `"30s"`).
    public var currentSetRepsDisplay: String
    /// One-line preview after the current set (e.g. `"Next: Set 3"`); `nil` when no further set planned.
    public var nextSetPreview: String?
    /// UTC ISO8601 wall-clock end of the post-rest "GO / Start your next set" attention window. Watch shows the GO state until `now < restAttentionExpiresAt`.
    public var restAttentionExpiresAt: String?

    enum CodingKeys: String, CodingKey {
        case watchConnectivitySchemaVersion
        case sessionId
        case workoutStartedAt
        case phase
        case currentExerciseName
        case completedSetCount
        case restEndsAt
        case restStartedAt
        case healthSyncEnabled
        case watchRunsHealthKitSession
        case currentSetTitle
        case currentSetWeightDisplay
        case currentSetRepsDisplay
        case nextSetPreview
        case restAttentionExpiresAt
    }

    public init(
        sessionId: String,
        workoutStartedAt: String?,
        phase: Phase,
        currentExerciseName: String,
        completedSetCount: Int,
        restEndsAt: String?,
        restStartedAt: String?,
        healthSyncEnabled: Bool,
        watchRunsHealthKitSession: Bool? = nil,
        currentSetTitle: String = "",
        currentSetWeightDisplay: String = "—",
        currentSetRepsDisplay: String = "—",
        nextSetPreview: String? = nil,
        restAttentionExpiresAt: String? = nil,
        watchConnectivitySchemaVersion: Int = WatchActiveWorkoutSnapshot.currentWatchConnectivitySchemaVersion
    ) {
        self.watchConnectivitySchemaVersion = watchConnectivitySchemaVersion
        self.sessionId = sessionId
        self.workoutStartedAt = workoutStartedAt
        self.phase = phase
        self.currentExerciseName = currentExerciseName
        self.completedSetCount = completedSetCount
        self.restEndsAt = restEndsAt
        self.restStartedAt = restStartedAt
        self.healthSyncEnabled = healthSyncEnabled
        self.watchRunsHealthKitSession = watchRunsHealthKitSession
        self.currentSetTitle = currentSetTitle
        self.currentSetWeightDisplay = currentSetWeightDisplay
        self.currentSetRepsDisplay = currentSetRepsDisplay
        self.nextSetPreview = nextSetPreview
        self.restAttentionExpiresAt = restAttentionExpiresAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        watchConnectivitySchemaVersion = try c.decodeIfPresent(Int.self, forKey: .watchConnectivitySchemaVersion) ?? 1
        sessionId = try c.decode(String.self, forKey: .sessionId)
        workoutStartedAt = try c.decodeIfPresent(String.self, forKey: .workoutStartedAt)
        phase = try c.decode(Phase.self, forKey: .phase)
        currentExerciseName = try c.decode(String.self, forKey: .currentExerciseName)
        completedSetCount = try c.decode(Int.self, forKey: .completedSetCount)
        restEndsAt = try c.decodeIfPresent(String.self, forKey: .restEndsAt)
        restStartedAt = try c.decodeIfPresent(String.self, forKey: .restStartedAt)
        healthSyncEnabled = try c.decode(Bool.self, forKey: .healthSyncEnabled)
        watchRunsHealthKitSession = try c.decodeIfPresent(Bool.self, forKey: .watchRunsHealthKitSession)
        currentSetTitle = try c.decodeIfPresent(String.self, forKey: .currentSetTitle) ?? ""
        currentSetWeightDisplay = try c.decodeIfPresent(String.self, forKey: .currentSetWeightDisplay) ?? "—"
        currentSetRepsDisplay = try c.decodeIfPresent(String.self, forKey: .currentSetRepsDisplay) ?? "—"
        nextSetPreview = try c.decodeIfPresent(String.self, forKey: .nextSetPreview)
        restAttentionExpiresAt = try c.decodeIfPresent(String.self, forKey: .restAttentionExpiresAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(watchConnectivitySchemaVersion, forKey: .watchConnectivitySchemaVersion)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encodeIfPresent(workoutStartedAt, forKey: .workoutStartedAt)
        try c.encode(phase, forKey: .phase)
        try c.encode(currentExerciseName, forKey: .currentExerciseName)
        try c.encode(completedSetCount, forKey: .completedSetCount)
        try c.encodeIfPresent(restEndsAt, forKey: .restEndsAt)
        try c.encodeIfPresent(restStartedAt, forKey: .restStartedAt)
        try c.encode(healthSyncEnabled, forKey: .healthSyncEnabled)
        try c.encodeIfPresent(watchRunsHealthKitSession, forKey: .watchRunsHealthKitSession)
        try c.encode(currentSetTitle, forKey: .currentSetTitle)
        try c.encode(currentSetWeightDisplay, forKey: .currentSetWeightDisplay)
        try c.encode(currentSetRepsDisplay, forKey: .currentSetRepsDisplay)
        try c.encodeIfPresent(nextSetPreview, forKey: .nextSetPreview)
        try c.encodeIfPresent(restAttentionExpiresAt, forKey: .restAttentionExpiresAt)
    }
}

// MARK: - Future (Phase 3): Hevy-style wrist-first logging
// Pairing a shared App Group container with GRDB would let the Watch log sets offline and merge into the
// phone’s canonical DB when reachable—large persistence migration; keep phone-only writer until then.

/// Keys and command strings shared between iPhone and Watch (avoid typos).
public enum WatchConnectivityPayload {
    public static let snapshotJSONKey = "watchSnapshotJSON"
    public static let cmdKey = "cmd"

    public static let cmdPrepareHK = "prepareHK"
    public static let cmdHKReady = "hkReady"
    public static let cmdFinishHK = "finishHK"
    public static let cmdDiscardHK = "discardHK"

    public static let sessionIdKey = "sessionId"
    public static let workoutStartedAtKey = "workoutStartedAt"
    public static let endedAtKey = "endedAt"

    /// Watch → iPhone: live BPM from ``HKLiveWorkoutBuilder`` (not HealthKit mirror latency).
    public static let liveHeartRateBpmKey = "liveHeartBpm"
    public static let liveHeartRateMeasuredAtKey = "liveHeartAt"
}
