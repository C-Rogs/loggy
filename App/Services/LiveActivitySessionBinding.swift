import Foundation

/// Pure rules for when a Live Activity should be replaced or accept updates (testable without ActivityKit).
public enum LiveActivitySessionBinding {
    /// When an activity already exists, returns whether its session id differs from `requestedSessionId` (caller should end first).
    public static func shouldEndBeforeStarting(existingSessionId: String, requestedSessionId: String) -> Bool {
        existingSessionId != requestedSessionId
    }

    /// Whether an update payload should be applied to the activity bound to `boundSessionId`.
    public static func shouldAcceptUpdate(boundSessionId: String, updateSessionId: String) -> Bool {
        boundSessionId == updateSessionId
    }
}
