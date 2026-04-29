import SwiftUI

enum ExerciseSummaryRowStyle {
    /// Exercise browse screen (navigation rows).
    case directory
    /// Picker sheets and compact lists (replace exercise, add to workout).
    case list
}

struct ExerciseSummaryRowLabel: View {
    let exercise: ExerciseSummary
    var style: ExerciseSummaryRowStyle = .list

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.displayName)
                .font(style == .directory ? .headline : .body)
                .multilineTextAlignment(.leading)
            Text(exercise.exerciseMode.rawValue.replacingOccurrences(of: "_", with: " "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let m = exercise.primaryMuscleGroup, !m.isEmpty {
                Text(MuscleDisplayName.forStoredSlug(m))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
