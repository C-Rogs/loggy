import Foundation

/// Builds the lock-screen subtitle for the next planned set (same exercise or next exercise).
public enum LiveActivitySetPreviewFormatter {
    public static let maxExerciseNameLength = 22

    public static func setLabelForPreview(_ set: SetRowModel) -> String {
        switch set.setType {
        case .warmup: return "W"
        default: return "Set \(set.setIndex + 1)"
        }
    }

    /// Weight and reps (or duration/distance) strings aligned with `ActiveWorkoutViewModel` live activity displays.
    public static func weightAndRepsDisplay(mode: ExerciseMode, set: SetRowModel) -> (String, String) {
        switch mode {
        case .weightReps:
            let kg: String = {
                guard let w = set.weightKg else { return "—" }
                return String(format: "%.1f kg", w)
            }()
            let r = set.reps.map { String($0) } ?? "—"
            return (kg, r)
        case .bodyweightReps:
            return ("—", set.reps.map { String($0) } ?? "—")
        case .duration:
            return ("—", set.durationSeconds.map { "\($0)s" } ?? "—")
        case .distanceDuration:
            let dist: String = {
                guard let d = set.distanceKm else { return "—" }
                return String(format: "%.2f km", d)
            }()
            let dur = set.durationSeconds.map { "\($0)s" } ?? "—"
            return (dist, dur)
        }
    }

    public static func truncateExerciseName(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= maxExerciseNameLength { return t }
        return String(t.prefix(maxExerciseNameLength)) + "…"
    }

    /// Next planned line after `currentSetId` on `card` within `exercises` order. Returns `"—"` when none.
    public static func nextPlannedSetLine(
        exercises: [SessionExerciseCard],
        card: SessionExerciseCard,
        currentSetId: String
    ) -> String {
        guard let si = card.sets.firstIndex(where: { $0.id == currentSetId }) else { return "—" }
        if si + 1 < card.sets.count {
            let n = card.sets[si + 1]
            let label = setLabelForPreview(n)
            let parts = weightAndRepsDisplay(mode: card.exerciseMode, set: n)
            return "\(label): \(parts.0) x \(parts.1)"
        }
        if let ci = exercises.firstIndex(where: { $0.id == card.id }), ci + 1 < exercises.count {
            let nex = exercises[ci + 1]
            guard let fs = nex.sets.first else { return "—" }
            let exLabel = truncateExerciseName(nex.displayName)
            let parts = weightAndRepsDisplay(mode: nex.exerciseMode, set: fs)
            return "\(exLabel): \(parts.0) x \(parts.1)"
        }
        return "—"
    }
}
