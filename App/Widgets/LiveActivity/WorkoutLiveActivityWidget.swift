import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLiveActivityLockScreenView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.55))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("\(context.state.completedSetCount) sets")
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    restExpandedLabel(state: context.state)
                }
            } compactLeading: {
                if let end = context.state.restEndsAt {
                    Text(end, style: .timer)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                } else {
                    Image(systemName: "dumbbell")
                }
            } compactTrailing: {
                if context.state.restEndsAt != nil {
                    Text("Rest")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(context.state.elapsedSeconds / 60)m")
                        .font(.caption2)
                        .monospacedDigit()
                }
            } minimal: {
                if let end = context.state.restEndsAt {
                    Text(end, style: .timer)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                } else {
                    Image(systemName: "dumbbell")
                }
            }
        }
    }
}

@ViewBuilder
private func restExpandedLabel(state: WorkoutActivityAttributes.ContentState) -> some View {
    if let end = state.restEndsAt {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Rest")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(end, style: .timer)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
    } else if let r = state.restRemainingSeconds {
        Text("Rest \(r)s")
            .font(.caption)
            .monospacedDigit()
    }
}

private struct WorkoutLiveActivityLockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.currentExerciseName)
                .font(.headline)
            HStack {
                Text(formatClock(state.elapsedSeconds))
                    .font(.caption)
                    .monospacedDigit()
                Spacer()
                if let end = state.restEndsAt {
                    Text(end, style: .timer)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                } else if let r = state.restRemainingSeconds {
                    Text("Rest \(r)s")
                        .font(.caption)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func formatClock(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
