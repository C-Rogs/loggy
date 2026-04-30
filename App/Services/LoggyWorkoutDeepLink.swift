import Foundation

extension Notification.Name {
    /// Posted after a `loggy://` live workout URL mutates the active session (so in-app UI can reload).
    static let loggyActiveWorkoutMutated = Notification.Name("loggyActiveWorkoutMutated")

    /// Posted on iPhone when `WCSession.isReachable` becomes true (Watch woke / Loggy opened on Watch).
    static let loggyWatchReachabilityDidBecomeReachable = Notification.Name("loggyWatchReachabilityDidBecomeReachable")
}

/// `loggy://workout/live-action?...` URLs opened from the Live Activity (lock screen).
enum LoggyWorkoutDeepLink {
    static let scheme = "loggy"
    static let host = "workout"
    static let path = "/live-action"

    enum Op: String {
        case complete
        case weightDelta = "weight_delta"
        case repsDelta = "reps_delta"
        case skipRest = "skip_rest"
    }

    struct Parsed: Equatable {
        var op: Op
        var sessionId: String
        var wse: String?
        var setId: String?
        var delta: Double?
    }

    static func parse(_ url: URL) -> Parsed? {
        guard url.scheme == scheme, url.host == host, url.path == path else { return nil }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func val(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard let opRaw = val("op"), let op = Op(rawValue: opRaw),
              let sid = val("sid"), !sid.isEmpty
        else { return nil }
        let wse = val("wse")
        let set = val("set")
        let d = val("d").flatMap(Double.init)
        return Parsed(op: op, sessionId: sid, wse: wse, setId: set, delta: d)
    }

    /// Build a URL for `Link` in the Live Activity widget.
    static func actionURL(sessionId: String, op: Op, wse: String?, setId: String?, delta: Double?) -> URL? {
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        c.path = path
        var items: [URLQueryItem] = [
            URLQueryItem(name: "op", value: op.rawValue),
            URLQueryItem(name: "sid", value: sessionId)
        ]
        if let wse { items.append(URLQueryItem(name: "wse", value: wse)) }
        if let setId { items.append(URLQueryItem(name: "set", value: setId)) }
        if let delta {
            items.append(URLQueryItem(name: "d", value: String(delta)))
        }
        c.queryItems = items
        return c.url
    }
}
