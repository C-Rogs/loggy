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
                    if let r = context.state.restRemainingSeconds {
                        Text("Rest \(r)s")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell")
            } compactTrailing: {
                if let r = context.state.restRemainingSeconds {
                    Text("\(r)s").font(.caption2).monospacedDigit()
                } else {
                    Text("\(context.state.elapsedSeconds / 60)m")
                        .font(.caption2)
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: "timer")
            }
        }
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
                if let r = state.restRemainingSeconds {
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
