import AudioToolbox
import UIKit

/// Centralized haptics and short system sounds. Keep bursts short and meaningful (Duolingo-style: reward on milestones, light taps on frequent actions).
enum LoggyFeedback {
    /// Rest countdown reached zero (natural expiry, not skip).
    static func restTimerCompleted() {
        let notify = UINotificationFeedbackGenerator()
        notify.prepare()
        notify.notificationOccurred(.success)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        // Tri-tone “alert done” — clear in a gym; swap for a custom .caf later if desired.
        AudioServicesPlaySystemSound(1022)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.prepare()
            impact.impactOccurred(intensity: 0.85)
        }
    }

    static func setCompleted() {
        let n = UINotificationFeedbackGenerator()
        n.prepare()
        n.notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            let i = UIImpactFeedbackGenerator(style: .light)
            i.prepare()
            i.impactOccurred(intensity: 0.7)
        }
    }

    static func setUncompleted() {
        let s = UISelectionFeedbackGenerator()
        s.prepare()
        s.selectionChanged()
    }

    static func restSkipped() {
        let s = UISelectionFeedbackGenerator()
        s.prepare()
        s.selectionChanged()
    }

    static func restAdjusted() {
        let i = UIImpactFeedbackGenerator(style: .rigid)
        i.prepare()
        i.impactOccurred(intensity: 0.55)
    }

    static func workoutFinishedSaved() {
        let n = UINotificationFeedbackGenerator()
        n.prepare()
        n.notificationOccurred(.success)
    }

    static func workoutDiscarded() {
        let n = UINotificationFeedbackGenerator()
        n.prepare()
        n.notificationOccurred(.warning)
    }

    static func listSelectionTap() {
        let s = UISelectionFeedbackGenerator()
        s.prepare()
        s.selectionChanged()
    }

    static func primaryActionTap() {
        let i = UIImpactFeedbackGenerator(style: .light)
        i.prepare()
        i.impactOccurred(intensity: 0.65)
    }
}
