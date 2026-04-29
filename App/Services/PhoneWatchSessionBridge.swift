#if os(iOS)
import Foundation
import WatchConnectivity

/// Forwards active workout snapshots to the paired Apple Watch and coordinates Option A (Watch-owned HK workout).
///
/// **HealthKit strategy (Option A):** Avoid duplicate strength workouts in Health by letting the Watch own
/// ``HKLiveWorkoutBuilder`` when it acknowledges `prepareHK`; the iPhone skips ``HKWorkoutBuilder`` and only reads HR/energy.
/// Physical-device validation should confirm ring totals and HR continuity on real hardware.
@MainActor
final class PhoneWatchSessionBridge: NSObject, ObservableObject {
    static weak var shared: PhoneWatchSessionBridge?

    override init() {
        super.init()
        Self.shared = self
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Pushes mirror state; safe to call frequently (uses `updateApplicationContext`).
    func pushSnapshot(_ snapshot: WatchActiveWorkoutSnapshot) {
        guard WCSession.default.activationState == .activated else { return }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshot),
              let json = String(data: data, encoding: .utf8)
        else { return }
        do {
            try WCSession.default.updateApplicationContext([WatchConnectivityPayload.snapshotJSONKey: json])
        } catch {
            // Queue full or unreachable — ignore; next push retries.
        }
    }

    /// True when the Watch app is installed but not currently reachable — worth waiting/retrying before falling back to the phone-only HK builder.
    func shouldDeferPhoneBuilderForWatchRetry() -> Bool {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled
        else { return false }
        return !WCSession.default.isReachable
    }

    /// Returns true if Watch will own the HealthKit workout for this session (Option A).
    func requestWatchOwnsHealthWorkout(sessionId: String, sessionStartedAt: Date) async -> Bool {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled else { return false }

        let started = ISO8601UTC.string(from: sessionStartedAt)
        let payload: [String: Any] = [
            WatchConnectivityPayload.cmdKey: WatchConnectivityPayload.cmdPrepareHK,
            WatchConnectivityPayload.sessionIdKey: sessionId,
            WatchConnectivityPayload.workoutStartedAtKey: started,
        ]

        return await withCheckedContinuation { continuation in
            guard WCSession.default.isReachable else {
                continuation.resume(returning: false)
                return
            }
            WCSession.default.sendMessage(payload, replyHandler: { reply in
                let cmd = reply[WatchConnectivityPayload.cmdKey] as? String
                continuation.resume(returning: cmd == WatchConnectivityPayload.cmdHKReady)
            }, errorHandler: { _ in
                continuation.resume(returning: false)
            })
        }
    }

    func requestWatchFinishHealthWorkout(endedAt: Date) async {
        await sendHKLifecycleCommand(cmd: WatchConnectivityPayload.cmdFinishHK, endedAt: endedAt)
    }

    func requestWatchDiscardHealthWorkout() async {
        await sendHKLifecycleCommand(cmd: WatchConnectivityPayload.cmdDiscardHK, endedAt: nil)
    }

    private func sendHKLifecycleCommand(cmd: String, endedAt: Date?) async {
        guard WCSession.default.activationState == .activated else { return }
        var payload: [String: Any] = [WatchConnectivityPayload.cmdKey: cmd]
        if let endedAt {
            payload[WatchConnectivityPayload.endedAtKey] = ISO8601UTC.string(from: endedAt)
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            if WCSession.default.isReachable {
                WCSession.default.sendMessage(payload, replyHandler: { _ in
                    cont.resume()
                }, errorHandler: { _ in
                    cont.resume()
                })
            } else {
                cont.resume()
            }
        }
    }
}

extension PhoneWatchSessionBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            WCSession.default.activate()
        }
    }
}
#endif
