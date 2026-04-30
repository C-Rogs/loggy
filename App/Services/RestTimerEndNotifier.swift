import Foundation
import UserNotifications
import os.log

extension Logger {
    /// Rest-timer local notifications (optional; denied authorization is debug-logged only).
    static let restNotification = Logger(subsystem: "com.loggy.app", category: "restNotification")
}

/// Schedules a one-shot local alert when a rest interval ends (works when the app is backgrounded or the screen is locked).
enum RestTimerEndNotifier {
    private static let center = UNUserNotificationCenter.current()

    static func identifier(forTimerId timerId: String) -> String {
        "loggy-rest-done-\(timerId)"
    }

    static func cancel(timerId: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(forTimerId: timerId)])
    }

    /// Schedules or replaces the pending “rest done” notification; no-op if the fire time is too soon or already passed.
    static func scheduleIfNeeded(timerId: String, endsAt: Date) {
        let interval = endsAt.timeIntervalSinceNow
        guard interval > 1 else {
            cancel(timerId: timerId)
            return
        }

        // Clear any in-flight request immediately so concurrent `Task` invocations cannot stack duplicate `add` calls
        // before a prior `cancel` runs (see `Task` body).
        cancel(timerId: timerId)

        Task { @MainActor in
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            } else if settings.authorizationStatus != .authorized {
                #if DEBUG
                Logger.restNotification.debug(
                    "Rest-end notification skipped: authorization \(String(describing: settings.authorizationStatus), privacy: .public)"
                )
                #endif
                return
            }

            cancel(timerId: timerId)

            let intervalNow = endsAt.timeIntervalSinceNow
            guard intervalNow > 1 else {
                cancel(timerId: timerId)
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Rest done"
            content.body = "Start your next set."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: intervalNow, repeats: false)
            let request = UNNotificationRequest(identifier: identifier(forTimerId: timerId), content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
