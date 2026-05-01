import Foundation
import HealthKit
import WatchConnectivity

@MainActor
final class WatchSessionCoordinator: NSObject, ObservableObject {
    /// Set from `init` so ``WKApplicationDelegate`` can start HK after ``HKHealthStore/startWatchApp(toHandle:)`` on iPhone.
    static weak var shared: WatchSessionCoordinator?

    @Published private(set) var snapshot: WatchActiveWorkoutSnapshot?
    /// Latest BPM read from the Watch ``HKLiveWorkoutBuilder`` so the on-wrist UI can show it without round-tripping through the phone.
    @Published private(set) var liveHeartRateBpm: Int?
    @Published private(set) var liveHeartRateMeasuredAt: Date?

    private let hkController = WatchHealthWorkoutSessionController()
    /// ``HKHealthStore/startWatchApp(toHandle:)`` can run before WC delivers the snapshot — finish starting HK once session id is known.
    private var pendingHealthKitLaunchConfiguration: HKWorkoutConfiguration?

    override init() {
        super.init()
        Self.shared = self
        hkController.onLiveHeartRate = { [weak self] bpm, at in
            guard let self else { return }
            self.liveHeartRateBpm = bpm
            self.liveHeartRateMeasuredAt = at
            self.sendLiveHeartRateToPhone(bpm: bpm, measuredAt: at)
        }
        if WCSession.isSupported() {
            let s = WCSession.default
            s.delegate = self
            s.activate()
        }
    }

    private func sendLiveHeartRateToPhone(bpm: Int, measuredAt: Date) {
        let payload: [String: Any] = [
            WatchConnectivityPayload.liveHeartRateBpmKey: bpm,
            WatchConnectivityPayload.liveHeartRateMeasuredAtKey: ISO8601UTC.string(from: measuredAt),
        ]
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: { _ in },
                errorHandler: { _ in
                    session.transferUserInfo(payload)
                }
            )
        } else {
            session.transferUserInfo(payload)
        }
    }

    /// After Watch ``HKLiveWorkoutSession`` is running, notify iPhone so it does not fall back to a duplicate phone workout while WC was asleep.
    private func notifyPhoneHKReady(sessionId: String) {
        let payload: [String: Any] = [
            WatchConnectivityPayload.cmdKey: WatchConnectivityPayload.cmdHKReady,
            WatchConnectivityPayload.sessionIdKey: sessionId,
        ]
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        session.transferUserInfo(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { _ in }, errorHandler: { _ in })
        }
    }

    /// Called when iPhone uses ``HKHealthStore/startWatchApp(toHandle:)`` with strength-training config — **before** WC may deliver `prepareHK`.
    func handleHealthKitWorkoutLaunch(configuration: HKWorkoutConfiguration) async {
        guard configuration.activityType == .traditionalStrengthTraining else { return }
        await hkController.requestAuthorization()

        var sessionId = ""
        var startedAt = Date()

        if let snap = snapshot {
            sessionId = snap.sessionId
            if let s = snap.workoutStartedAt, let d = ISO8601UTC.date(from: s) {
                startedAt = d
            }
        } else {
            let ctx = WCSession.default.receivedApplicationContext
            guard let json = ctx[WatchConnectivityPayload.snapshotJSONKey] as? String,
                  let data = json.data(using: .utf8),
                  let snap = try? JSONDecoder().decode(WatchActiveWorkoutSnapshot.self, from: data)
            else {
                pendingHealthKitLaunchConfiguration = configuration
                return
            }
            snapshot = snap
            sessionId = snap.sessionId
            if let s = snap.workoutStartedAt, let d = ISO8601UTC.date(from: s) {
                startedAt = d
            }
        }

        guard !sessionId.isEmpty else {
            pendingHealthKitLaunchConfiguration = configuration
            return
        }

        if snapshot?.watchRunsHealthKitSession == false {
            pendingHealthKitLaunchConfiguration = nil
            return
        }

        /// Don’t start sensors until the phone explicitly selects Watch as HK writer (`true`). If `nil`, wait for an updated snapshot or `prepareHK`.
        guard snapshot?.watchRunsHealthKitSession == true else {
            pendingHealthKitLaunchConfiguration = configuration
            return
        }

        pendingHealthKitLaunchConfiguration = nil
        let ok = await hkController.start(sessionId: sessionId, startedAt: startedAt, workoutConfiguration: configuration)
        if ok {
            notifyPhoneHKReady(sessionId: sessionId)
        }
    }

    private func applyContext(_ context: [String: Any]) {
        guard let json = context[WatchConnectivityPayload.snapshotJSONKey] as? String,
              let data = json.data(using: .utf8)
        else { return }
        let dec = JSONDecoder()
        if let snap = try? dec.decode(WatchActiveWorkoutSnapshot.self, from: data) {
            let prevPhase = snapshot?.phase
            let prevAttention = snapshot?.restAttentionExpiresAt
            snapshot = snap
            // Tactile cues mirror Hevy: a `.start` haptic when entering active, `.stop` when leaving, `.success` when the post-rest "GO" attention banner first appears.
            if prevPhase != .active, snap.phase == .active {
                LoggyWatchFeedback.workoutStarted()
            } else if prevPhase == .active, snap.phase != .active {
                LoggyWatchFeedback.workoutEnded()
            }
            if prevAttention == nil, snap.restAttentionExpiresAt != nil {
                LoggyWatchFeedback.restExpired()
            }
            Task { @MainActor in
                await self.tryCompletePendingHealthKitLaunch()
                await self.maybeStartHealthKitFromSnapshot(snap)
            }
        }
    }

    private func maybeStartHealthKitFromSnapshot(_ snap: WatchActiveWorkoutSnapshot) async {
        guard snap.phase == .active,
              snap.healthSyncEnabled,
              snap.watchRunsHealthKitSession == true,
              !snap.sessionId.isEmpty
        else { return }
        if hkController.isActiveForLoggySession(sessionId: snap.sessionId) { return }
        guard let startedStr = snap.workoutStartedAt, let started = ISO8601UTC.date(from: startedStr) else { return }
        let ok = await hkController.start(sessionId: snap.sessionId, startedAt: started, workoutConfiguration: nil)
        if ok {
            notifyPhoneHKReady(sessionId: snap.sessionId)
        }
    }

    private func tryCompletePendingHealthKitLaunch() async {
        guard let configuration = pendingHealthKitLaunchConfiguration else { return }
        guard let snap = snapshot, !snap.sessionId.isEmpty else { return }
        if snap.watchRunsHealthKitSession == false {
            pendingHealthKitLaunchConfiguration = nil
            return
        }
        guard snap.watchRunsHealthKitSession == true else { return }
        var startedAt = Date()
        if let s = snap.workoutStartedAt, let d = ISO8601UTC.date(from: s) {
            startedAt = d
        }
        pendingHealthKitLaunchConfiguration = nil
        let ok = await hkController.start(sessionId: snap.sessionId, startedAt: startedAt, workoutConfiguration: configuration)
        if ok {
            notifyPhoneHKReady(sessionId: snap.sessionId)
        }
    }

    private func handleMessage(_ message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let cmd = message[WatchConnectivityPayload.cmdKey] as? String
        switch cmd {
        case WatchConnectivityPayload.cmdPrepareHK:
            let sid = message[WatchConnectivityPayload.sessionIdKey] as? String ?? ""
            let startedStr = message[WatchConnectivityPayload.workoutStartedAtKey] as? String
            let started = startedStr.flatMap { ISO8601UTC.date(from: $0) } ?? Date()
            Task { @MainActor in
                await self.runPrepareHealthKit(sessionId: sid, startedAt: started, replyHandler: replyHandler)
            }
        case WatchConnectivityPayload.cmdFinishHK:
            let endedStr = message[WatchConnectivityPayload.endedAtKey] as? String
            let ended = endedStr.flatMap { ISO8601UTC.date(from: $0) } ?? Date()
            Task { @MainActor in
                await self.hkController.finish(endedAt: ended)
                replyHandler([WatchConnectivityPayload.cmdKey: "ok"])
            }
        case WatchConnectivityPayload.cmdDiscardHK:
            Task { @MainActor in
                self.hkController.discard()
                replyHandler([WatchConnectivityPayload.cmdKey: "ok"])
            }
        default:
            replyHandler([:])
        }
    }

    /// `prepareHK` from immediate message, queued `transferUserInfo`, or both.
    private func runPrepareHealthKit(
        sessionId sid: String,
        startedAt started: Date,
        replyHandler: (([String: Any]) -> Void)?
    ) async {
        if hkController.isActiveForLoggySession(sessionId: sid) {
            notifyPhoneHKReady(sessionId: sid)
            replyHandler?([WatchConnectivityPayload.cmdKey: WatchConnectivityPayload.cmdHKReady])
            return
        }
        let ok = await hkController.start(sessionId: sid, startedAt: started, workoutConfiguration: nil)
        if ok {
            notifyPhoneHKReady(sessionId: sid)
            replyHandler?([WatchConnectivityPayload.cmdKey: WatchConnectivityPayload.cmdHKReady])
        } else {
            replyHandler?([:])
        }
    }

    private func handleQueuedUserInfo(_ userInfo: [String: Any]) {
        let cmd = userInfo[WatchConnectivityPayload.cmdKey] as? String
        guard cmd == WatchConnectivityPayload.cmdPrepareHK else { return }
        let sid = userInfo[WatchConnectivityPayload.sessionIdKey] as? String ?? ""
        let startedStr = userInfo[WatchConnectivityPayload.workoutStartedAtKey] as? String
        let started = startedStr.flatMap { ISO8601UTC.date(from: $0) } ?? Date()
        Task { @MainActor in
            await self.runPrepareHealthKit(sessionId: sid, startedAt: started, replyHandler: nil)
        }
    }
}

extension WatchSessionCoordinator: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.applyContext(WCSession.default.receivedApplicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyContext(applicationContext)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            self.handleMessage(message, replyHandler: replyHandler)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            self.handleQueuedUserInfo(userInfo)
        }
    }
}
