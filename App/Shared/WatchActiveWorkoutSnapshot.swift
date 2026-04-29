import Foundation

/// Payload mirrored to Apple Watch via Watch Connectivity (ISO 8601 UTC strings per persistence rules).
public struct WatchActiveWorkoutSnapshot: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case idle
        case active
        case ending
    }

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

    public init(
        sessionId: String,
        workoutStartedAt: String?,
        phase: Phase,
        currentExerciseName: String,
        completedSetCount: Int,
        restEndsAt: String?,
        restStartedAt: String?,
        healthSyncEnabled: Bool
    ) {
        self.sessionId = sessionId
        self.workoutStartedAt = workoutStartedAt
        self.phase = phase
        self.currentExerciseName = currentExerciseName
        self.completedSetCount = completedSetCount
        self.restEndsAt = restEndsAt
        self.restStartedAt = restStartedAt
        self.healthSyncEnabled = healthSyncEnabled
    }
}

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
}
