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

    /// First tap on an inline destructive button — the action is now armed and waiting for a confirmation tap.
    static func destructiveArmed() {
        let n = UINotificationFeedbackGenerator()
        n.prepare()
        n.notificationOccurred(.warning)
    }

    /// Second tap that actually fires the destructive action.
    static func destructiveCommitted() {
        let n = UINotificationFeedbackGenerator()
        n.prepare()
        n.notificationOccurred(.error)
    }

    /// Inline destructive button reverted before the second tap.
    static func destructiveCancelled() {
        let s = UISelectionFeedbackGenerator()
        s.prepare()
        s.selectionChanged()
    }

    /// Picker / segmented control / wheel changed value.
    static func picker() {
        Self.throttle(.picker) {
            let s = UISelectionFeedbackGenerator()
            s.prepare()
            s.selectionChanged()
        }
    }

    /// Stepper / numeric tap (kg/reps).
    static func numericIncrement() {
        Self.throttle(.numericIncrement) {
            let i = UIImpactFeedbackGenerator(style: .rigid)
            i.prepare()
            i.impactOccurred(intensity: 0.45)
        }
    }

    /// User-initiated sheet presentation.
    static func sheetOpened() {
        let i = UIImpactFeedbackGenerator(style: .soft)
        i.prepare()
        i.impactOccurred(intensity: 0.55)
    }

    static func tabChanged() {
        let s = UISelectionFeedbackGenerator()
        s.prepare()
        s.selectionChanged()
    }

    static func toggleOn() {
        let i = UIImpactFeedbackGenerator(style: .light)
        i.prepare()
        i.impactOccurred(intensity: 0.7)
    }

    static func toggleOff() {
        let i = UIImpactFeedbackGenerator(style: .light)
        i.prepare()
        i.impactOccurred(intensity: 0.45)
    }

    // MARK: - Throttle

    private enum ThrottleKey: String { case picker, numericIncrement }

    private static var lastFireAt: [ThrottleKey: TimeInterval] = [:]
    private static let throttleInterval: TimeInterval = 0.2

    /// Skip rapid bursts so a long-press / repeat tap doesn't buzz continuously.
    private static func throttle(_ key: ThrottleKey, _ work: () -> Void) {
        let now = Date().timeIntervalSinceReferenceDate
        if let last = lastFireAt[key], now - last < throttleInterval { return }
        lastFireAt[key] = now
        work()
    }
}
