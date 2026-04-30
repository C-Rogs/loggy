#if os(iOS)
import Foundation
import WatchConnectivity

/// Forwards active workout snapshots to the paired Apple Watch and receives live heart rate / HK-ready signals.
///
/// **Watch-primary HK:** ``transferUserInfo`` always queues ``prepareHK`` so the Watch can start ``HKLiveWorkoutSession``
/// after wake; ``sendMessage`` is used when reachable for an immediate reply. The Watch also pushes ``hkReady``
/// asynchronously so the phone does not fall back to a duplicate phone ``HKWorkoutBuilder`` while the Watch is asleep.
@MainActor
final class PhoneWatchSessionBridge: NSObject, ObservableObject {
    static weak var shared: PhoneWatchSessionBridge?

    /// Watch ``HKLiveWorkoutBuilder`` forwards BPM here (see ``WatchConnectivityPayload/liveHeartRateBpmKey``).
    var onLiveHeartRateFromWatch: ((Int, Date) -> Void)?

    /// Latest encoded snapshot while `WCSession` is still activating (first pushes often happened before activation completed).
    private var pendingSnapshotJSON: String?

    /// Single in-flight wait for Watch ``hkReady`` (matches one Loggy session id).
    private var pendingHKReadyGate: HKReadyGate?

    private static let watchHKHandshakeTimeoutSeconds: TimeInterval = 25

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
    /// Does nothing when no paired Watch or LoggyWatch is not installed (`WCErrorCodeWatchAppNotInstalled` otherwise).
    func pushSnapshot(_ snapshot: WatchActiveWorkoutSnapshot) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshot),
              let json = String(data: data, encoding: .utf8)
        else { return }

        let session = WCSession.default
        guard session.isWatchAppInstalled else {
            pendingSnapshotJSON = nil
            return
        }

        switch session.activationState {
        case .activated:
            pendingSnapshotJSON = nil
            do {
                try session.updateApplicationContext([WatchConnectivityPayload.snapshotJSONKey: json])
            } catch {
                pendingSnapshotJSON = json
            }
        case .inactive, .notActivated:
            pendingSnapshotJSON = json
        @unknown default:
            pendingSnapshotJSON = json
        }
    }

    private func flushPendingSnapshotIfNeeded() {
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isWatchAppInstalled,
              let json = pendingSnapshotJSON
        else { return }
        do {
            try session.updateApplicationContext([WatchConnectivityPayload.snapshotJSONKey: json])
            pendingSnapshotJSON = nil
        } catch {
            // Keep pendingSnapshotJSON for next attempt (e.g. Watch asleep).
        }
    }

    /// Queues ``prepareHK`` on the Watch (always) and waits for ``hkReady`` up to ``watchHKHandshakeTimeoutSeconds``.
    /// Returns true when the Watch confirms its ``HKLiveWorkoutSession`` is running for this Loggy session.
    func requestWatchOwnsHealthWorkout(sessionId: String, sessionStartedAt: Date) async -> Bool {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled
        else { return false }

        let payload = Self.prepareHKPayload(sessionId: sessionId, sessionStartedAt: sessionStartedAt)
        WCSession.default.transferUserInfo(payload)

        if WCSession.default.isReachable {
            let fastOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                WCSession.default.sendMessage(payload, replyHandler: { reply in
                    let cmd = reply[WatchConnectivityPayload.cmdKey] as? String
                    cont.resume(returning: cmd == WatchConnectivityPayload.cmdHKReady)
                }, errorHandler: { _ in
                    cont.resume(returning: false)
                })
            }
            if fastOK {
                cancelPendingHKReadyWait()
                return true
            }
        }

        return await waitForHKReadyNotification(sessionId: sessionId, timeoutSeconds: Self.watchHKHandshakeTimeoutSeconds)
    }

    private static func prepareHKPayload(sessionId: String, sessionStartedAt: Date) -> [String: Any] {
        [
            WatchConnectivityPayload.cmdKey: WatchConnectivityPayload.cmdPrepareHK,
            WatchConnectivityPayload.sessionIdKey: sessionId,
            WatchConnectivityPayload.workoutStartedAtKey: ISO8601UTC.string(from: sessionStartedAt),
        ]
    }

    private func waitForHKReadyNotification(sessionId: String, timeoutSeconds: TimeInterval) async -> Bool {
        cancelPendingHKReadyWait()
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let gate = HKReadyGate(sessionId: sessionId, continuation: cont)
            pendingHKReadyGate = gate
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                gate.completeTimeoutIfStillWaiting()
                if self.pendingHKReadyGate === gate {
                    self.pendingHKReadyGate = nil
                }
            }
        }
    }

    private func cancelPendingHKReadyWait() {
        pendingHKReadyGate?.cancel()
        pendingHKReadyGate = nil
    }

    private func ingestHKReadyFromWatch(sessionId: String) {
        guard let gate = pendingHKReadyGate, gate.sessionId == sessionId else { return }
        pendingHKReadyGate = nil
        gate.completeSuccess()
    }

    func requestWatchFinishHealthWorkout(endedAt: Date) async {
        await sendHKLifecycleCommand(cmd: WatchConnectivityPayload.cmdFinishHK, endedAt: endedAt)
    }

    func requestWatchDiscardHealthWorkout() async {
        await sendHKLifecycleCommand(cmd: WatchConnectivityPayload.cmdDiscardHK, endedAt: nil)
    }

    private func sendHKLifecycleCommand(cmd: String, endedAt: Date?) async {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled
        else { return }
        var payload: [String: Any] = [WatchConnectivityPayload.cmdKey: cmd]
        if let endedAt {
            payload[WatchConnectivityPayload.endedAtKey] = ISO8601UTC.string(from: endedAt)
        }
        WCSession.default.transferUserInfo(payload)
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

    private func ingestPartnerPayload(_ dict: [String: Any]) {
        if dict[WatchConnectivityPayload.liveHeartRateBpmKey] != nil {
            ingestLiveHeartRateIfPresent(dict)
            return
        }
        if let cmd = dict[WatchConnectivityPayload.cmdKey] as? String,
           cmd == WatchConnectivityPayload.cmdHKReady,
           let sid = dict[WatchConnectivityPayload.sessionIdKey] as? String
        {
            ingestHKReadyFromWatch(sessionId: sid)
        }
    }

    private func ingestLiveHeartRateIfPresent(_ dict: [String: Any]) {
        let bpm: Int?
        if let i = dict[WatchConnectivityPayload.liveHeartRateBpmKey] as? Int {
            bpm = i
        } else if let d = dict[WatchConnectivityPayload.liveHeartRateBpmKey] as? Double {
            bpm = Int(round(d))
        } else {
            bpm = nil
        }
        guard let bpm else { return }
        let atStr = dict[WatchConnectivityPayload.liveHeartRateMeasuredAtKey] as? String
        let at = atStr.flatMap { ISO8601UTC.date(from: $0) } ?? Date()
        onLiveHeartRateFromWatch?(bpm, at)
    }
}

// MARK: - HK ready handshake

private final class HKReadyGate {
    let sessionId: String
    private var continuation: CheckedContinuation<Bool, Never>?
    private var finished = false

    init(sessionId: String, continuation: CheckedContinuation<Bool, Never>) {
        self.sessionId = sessionId
        self.continuation = continuation
    }

    func completeSuccess() {
        guard !finished else { return }
        finished = true
        continuation?.resume(returning: true)
        continuation = nil
    }

    func completeTimeoutIfStillWaiting() {
        guard !finished else { return }
        finished = true
        continuation?.resume(returning: false)
        continuation = nil
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        continuation?.resume(returning: false)
        continuation = nil
    }
}

extension PhoneWatchSessionBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            Self.shared?.flushPendingSnapshotIfNeeded()
            Self.shared?.objectWillChange.send()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            Self.shared?.objectWillChange.send()
            if session.isReachable {
                NotificationCenter.default.post(name: .loggyWatchReachabilityDidBecomeReachable, object: nil)
            }
        }
    }

    /// Paired Watch app install state changed (e.g. user installed LoggyWatch from App Store on Watch).
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            Self.shared?.flushPendingSnapshotIfNeeded()
            Self.shared?.objectWillChange.send()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            WCSession.default.activate()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            Self.shared?.ingestPartnerPayload(message)
            replyHandler([:])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            Self.shared?.ingestPartnerPayload(userInfo)
        }
    }
}
#endif
