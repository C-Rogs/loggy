import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLiveActivityLockScreenView(
                sessionId: context.attributes.workoutSessionId,
                state: context.state
            )
            .activityBackgroundTint(Color.primary.opacity(0.035))
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
                    DigitsRestCountdown(endsAt: end, useLarge: false)
                } else {
                    Image(systemName: "dumbbell")
                }
            } compactTrailing: {
                if context.state.restEndsAt != nil {
                    Text("Rest")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                } else if let start = context.state.workoutStartedAt {
                    DynamicIslandElapsedMinutes(startedAt: start)
                } else {
                    Text("\(context.state.elapsedSeconds / 60)m")
                        .font(.caption2)
                        .monospacedDigit()
                }
            } minimal: {
                if let end = context.state.restEndsAt {
                    DigitsRestCountdown(endsAt: end, useLarge: false)
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
            DigitsRestCountdown(endsAt: end, useLarge: true)
        }
    } else if let r = state.restRemainingSeconds {
        Text("Rest \(r)s")
            .font(.caption)
            .monospacedDigit()
    }
}

// MARK: - Lock screen

private struct WorkoutLiveActivityLockScreenView: View {
    let sessionId: String
    let state: WorkoutActivityAttributes.ContentState

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08))
                    Image("LoggyLockMark")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .padding(2)
                }
                .frame(width: 20, height: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                Text(loggyLockAppTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                LockScreenElapsedClock(workoutStartedAt: state.workoutStartedAt, fallbackSeconds: state.elapsedSeconds)
            }

            Text(state.currentExerciseName)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .padding(.top, 1)

            if !state.nextSetPreview.isEmpty {
                Text(state.nextSetPreview)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if isResting {
                LockScreenRestBlock(
                    endsAt: state.restEndsAt,
                    startedAt: state.restStartedAt,
                    fallbackProgress: state.restProgress
                )
            }

            lockScreenActions
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardFill)
        )
    }

    private var cardFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.09)
            : Color.white.opacity(0.38)
    }

    private var isResting: Bool {
        state.restEndsAt != nil || state.restRemainingSeconds != nil
    }

    /// Extension bundle matches `CFBundleDisplayName` in `App/Widgets/LiveActivity/Info.plist` (kept in sync with main app).
    private var loggyLockAppTitle: String {
        if let s = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !s.isEmpty { return s }
        if let s = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !s.isEmpty { return s }
        return "Loggy"
    }

    @ViewBuilder
    private var lockScreenActions: some View {
        let setId = state.liveSetEntryId
        let wse = state.liveSessionExerciseId
        VStack(spacing: 6) {
            if let w = wse, let s = setId,
               let completeURL = LoggyWorkoutDeepLink.actionURL(sessionId: sessionId, op: .complete, wse: w, setId: s, delta: nil)
            {
                HStack {
                    Spacer(minLength: 0)
                    if isResting {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle")
                                .font(.caption2.weight(.semibold))
                            Text("Done")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            markSetDoneDisabledFill,
                            in: Capsule(style: .continuous)
                        )
                        .accessibilityLabel("Mark set done, available when rest ends")
                    } else {
                        Link(destination: completeURL) {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2.weight(.bold))
                                Text("Done")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.green.opacity(0.88), in: Capsule(style: .continuous))
                        }
                        .accessibilityLabel("Mark set done")
                    }
                    Spacer(minLength: 0)
                }
            }
            if isResting,
               let skipURL = LoggyWorkoutDeepLink.actionURL(sessionId: sessionId, op: .skipRest, wse: nil, setId: nil, delta: nil)
            {
                Link(destination: skipURL) {
                    Text("Skip rest")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(.top, 2)
    }

    private var markSetDoneDisabledFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.10)
    }
}

/// Live elapsed time without per-second ActivityKit pushes — mirrors Now Playing’s anchored elapsed playback time (see `workoutStartedAt` in ``WorkoutActivityAttributes/ContentState``).
private struct LockScreenElapsedClock: View {
    let workoutStartedAt: Date?
    let fallbackSeconds: Int

    var body: some View {
        Group {
            if let start = workoutStartedAt {
                TimelineView(.periodic(from: Date(), by: 1.0)) { context in
                    let sec = max(0, Int(context.date.timeIntervalSince(start)))
                    Text(formatLockElapsed(sec))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                Text(formatLockElapsed(fallbackSeconds))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func formatLockElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct DynamicIslandElapsedMinutes: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            let sec = max(0, Int(context.date.timeIntervalSince(startedAt)))
            Text("\(sec / 60)m")
                .font(.caption2)
                .monospacedDigit()
        }
    }
}

// MARK: - Rest countdown (numeric only — avoids `Text(_, style: .timer)` locale words like “minute” overlapping digits)

private struct DigitsRestCountdown: View {
    let endsAt: Date
    var useLarge: Bool = false

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 0.1)) { context in
            let rem = max(0, Int(ceil(endsAt.timeIntervalSince(context.date))))
            Text(formatLockRestSeconds(rem))
                .font(useLarge ? .title3 : .caption2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
    }
}

private struct LockScreenRestBlock: View {
    let endsAt: Date?
    let startedAt: Date?
    let fallbackProgress: Double?

    var body: some View {
        Group {
            if let endsAt {
                TimelineView(.periodic(from: Date(), by: 0.1)) { context in
                    let now = context.date
                    let rawRem = endsAt.timeIntervalSince(now)
                    let remSec = max(0, Int(ceil(rawRem)))
                    let total: TimeInterval = {
                        if let s = startedAt {
                            return max(0.001, endsAt.timeIntervalSince(s))
                        }
                        if let fp = fallbackProgress, fp > 0.001, rawRem > 0 {
                            return max(0.001, rawRem / max(0.001, 1.0 - min(0.999, fp)))
                        }
                        return max(0.001, rawRem)
                    }()
                    let elapsed = max(0, total - max(0, rawRem))
                    let fraction = min(1, max(0, elapsed / total))

                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            let w = geo.size.width
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.22))
                                Capsule()
                                    .fill(Color.blue.opacity(0.92))
                                    .frame(width: max(3, w * CGFloat(fraction)))
                            }
                        }
                        .frame(height: 3)

                        HStack {
                            Text("Rest")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(formatLockRestSeconds(remSec))
                                .font(.title3)
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }
}

private func formatLockRestSeconds(_ totalSeconds: Int) -> String {
    let sec = max(0, totalSeconds)
    let m = sec / 60
    let s = sec % 60
    return "\(m):\(String(format: "%02d", s))"
}
