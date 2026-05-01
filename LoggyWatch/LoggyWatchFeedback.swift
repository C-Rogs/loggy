import Foundation
import WatchKit

/// Haptics on the Apple Watch via `WKInterfaceDevice`. Mirrors `LoggyFeedback` on iPhone but uses the limited haptic palette watchOS provides (`.click`, `.success`, `.start`, `.stop`, `.notification`, `.failure`).
enum LoggyWatchFeedback {
    /// Snapshot transitioned from idle/ending into `.active` (workout started).
    static func workoutStarted() {
        WKInterfaceDevice.current().play(.start)
    }

    /// Snapshot transitioned out of `.active` (workout finished or discarded).
    static func workoutEnded() {
        WKInterfaceDevice.current().play(.stop)
    }

    /// Rest just expired ("Start your next set" attention banner is now visible).
    static func restExpired() {
        WKInterfaceDevice.current().play(.success)
    }

    /// Heart rate just crossed up into a new effort zone for this set — light tactile cue.
    static func zoneCrossedUp() {
        WKInterfaceDevice.current().play(.click)
    }

    /// Communication failure / unrecoverable Watch error.
    static func failure() {
        WKInterfaceDevice.current().play(.failure)
    }
}
