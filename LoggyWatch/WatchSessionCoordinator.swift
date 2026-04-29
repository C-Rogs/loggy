import Foundation
import WatchConnectivity

@MainActor
final class WatchSessionCoordinator: NSObject, ObservableObject {
    @Published private(set) var snapshot: WatchActiveWorkoutSnapshot?

    private let hkController = WatchHealthWorkoutSessionController()

    override init() {
        super.init()
        if WCSession.isSupported() {
            let s = WCSession.default
            s.delegate = self
            s.activate()
        }
    }

    private func applyContext(_ context: [String: Any]) {
        guard let json = context[WatchConnectivityPayload.snapshotJSONKey] as? String,
              let data = json.data(using: .utf8)
        else { return }
        let dec = JSONDecoder()
        if let snap = try? dec.decode(WatchActiveWorkoutSnapshot.self, from: data) {
            snapshot = snap
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
                let ok = await self.hkController.start(sessionId: sid, startedAt: started)
                if ok {
                    replyHandler([WatchConnectivityPayload.cmdKey: WatchConnectivityPayload.cmdHKReady])
                } else {
                    replyHandler([:])
                }
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
}

extension WatchSessionCoordinator: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let ctx = WCSession.default.receivedApplicationContext as [String: Any]? {
                self.applyContext(ctx)
            }
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
}
