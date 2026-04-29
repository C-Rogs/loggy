import ActivityKit
import AppIntents
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(context.state.completedSetCount) sets")
                            .font(.caption)
                        IslandExpandedHealthGlance(state: context.state)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestExpandedIslandTrailing(state: context.state)
                }
            } compactLeading: {
                IslandCompactLeading(state: context.state)
            } compactTrailing: {
                IslandCompactTrailing(state: context.state)
            } minimal: {
                IslandMinimal(state: context.state)
            }
        }
    }
}

private func restAttentionActive(expiresAt: Date?, now: Date) -> Bool {
    guard let e = expiresAt else { return false }
    return now < e
}

private struct RestExpandedIslandTrailing: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { tl in
            if restAttentionActive(expiresAt: state.restAttentionExpiresAt, now: tl.date) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Rest done")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("GO")
                        .font(.title.weight(.heavy))
                        .foregroundStyle(.green)
                }
            } else if let end = state.restEndsAt {
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
    }
}

private struct IslandExpandedHealthGlance: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if let bpm = state.heartBpm {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.pink.opacity(0.95))
                Text("\(bpm) bpm")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
        } else if let tip = state.heartRateTip, !tip.isEmpty {
            Text(tip)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }
}

private struct IslandCompactLeading: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { tl in
            if restAttentionActive(expiresAt: state.restAttentionExpiresAt, now: tl.date) {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.green)
            } else if let end = state.restEndsAt {
                DigitsRestCountdown(endsAt: end, useLarge: false)
            } else {
                Image(systemName: "dumbbell")
            }
        }
    }
}

private struct IslandCompactTrailing: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { tl in
            if restAttentionActive(expiresAt: state.restAttentionExpiresAt, now: tl.date) {
                Text("GO")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.green)
            } else if state.restEndsAt != nil {
                Text("Rest")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            } else if let start = state.workoutStartedAt {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    DynamicIslandElapsedMinutes(startedAt: start)
                    if let bpm = state.heartBpm {
                        Text("·\(bpm)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.pink)
                            .monospacedDigit()
                    }
                }
            } else {
                Text("\(state.elapsedSeconds / 60)m")
                    .font(.caption2)
                    .monospacedDigit()
            }
        }
    }
}

private struct IslandMinimal: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { tl in
            if restAttentionActive(expiresAt: state.restAttentionExpiresAt, now: tl.date) {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.green)
            } else if let end = state.restEndsAt {
                DigitsRestCountdown(endsAt: end, useLarge: false)
            } else {
                Image(systemName: "dumbbell")
            }
        }
    }
}

// MARK: - Lock screen

private struct LockScreenRestAttentionBanner: View {
    let expiresAt: Date?

    var body: some View {
        Group {
            if let expiresAt {
                TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
                    if ctx.date < expiresAt {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.and.waves.left.and.right.fill")
                                .foregroundStyle(.green)
                                .imageScale(.medium)
                            Text("Start your next set")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

private struct LockScreenCurrentSetRow: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if !state.currentSetTitle.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(state.currentSetTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(state.currentKgDisplay)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text("×")
                        .foregroundStyle(.tertiary)
                    Text(state.currentRepsDisplay)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .minimumScaleFactor(0.88)
                .lineLimit(1)

                if state.previousDisplayCompact != "—" {
                    Text("Prev \(state.previousDisplayCompact)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.top, 1)
        }
    }
}

private struct LockScreenHealthGlanceBlock: View {
    let state: WorkoutActivityAttributes.ContentState

    private var showBlock: Bool {
        state.heartBpm != nil
            || !(state.activeKcalDisplay ?? "").isEmpty
            || !(state.heartRateTip ?? "").isEmpty
    }

    var body: some View {
        if showBlock {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    if let bpm = state.heartBpm {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red.opacity(0.92))
                            Text("\(bpm) bpm")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                    }
                    if let k = state.activeKcalDisplay, !k.isEmpty {
                        Text(k)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }

                if state.heartBpm == nil, let tip = state.heartRateTip, !tip.isEmpty {
                    Text(tip)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 2)
        }
    }
}

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

            LockScreenRestAttentionBanner(expiresAt: state.restAttentionExpiresAt)

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

            LockScreenCurrentSetRow(state: state)

            LockScreenHealthGlanceBlock(state: state)

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
            if let w = wse, let s = setId {
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
                        Button(
                            intent: LoggyMarkSetDoneLiveIntent(
                                sessionId: sessionId,
                                sessionExerciseId: w,
                                setEntryId: s
                            )
                        ) {
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
                        .buttonStyle(.plain)
                        .accessibilityLabel("Mark set done")
                    }
                    Spacer(minLength: 0)
                }
            }
            if isResting {
                Button(intent: LoggySkipRestLiveIntent(sessionId: sessionId)) {
                    Text("Skip rest")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
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
            if workoutStartedAt != nil || fallbackSeconds > 0 {
                TimelineView(.periodic(from: Date(), by: 1.0)) { context in
                    let sec = LiveActivityElapsedLogic.elapsedDisplaySeconds(
                        now: context.date,
                        workoutStartedAt: workoutStartedAt,
                        fallbackElapsedSeconds: fallbackSeconds
                    )
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
            let sec = LiveActivityElapsedLogic.elapsedDisplaySeconds(
                now: context.date,
                workoutStartedAt: startedAt,
                fallbackElapsedSeconds: 0
            )
            Text("\(sec / 60)m")
                .font(.caption2)
                .monospacedDigit()
        }
    }
}

// MARK: - Rest countdown
//
// - Avoid `Text(endsAt, style: .timer)`: after `endsAt` it counts *up* from zero.
// - Drive labels from `TimelineView` + `max(0, endsAt - now)` so display stops at 0.
// - Use a steady 4 Hz tick during rest for a smooth bar + responsive sub‑30s display (short intervals only).
// - When `startedAt` exists, use SwiftUI’s linear `ProgressView(timerInterval:countsDown:)` (native countdown progress).

private enum LiveActivityRestFormat {
    /// Seconds-first when under 30s (larger readout on lock screen / expanded island; scaled-down in compact island).
    static func display(remaining: TimeInterval, islandCompact: Bool) -> (text: String, font: Font?) {
        let rem = max(0, remaining)
        let sec = Int(ceil(rem))
        if sec == 0 {
            let size: CGFloat = islandCompact ? 12 : 28
            return ("0s", .system(size: size, weight: .bold, design: .rounded))
        }
        if sec < 30 {
            let t = "\(sec)s"
            let size: CGFloat = islandCompact ? 15 : 34
            return (t, .system(size: size, weight: .bold, design: .rounded))
        }
        let m = sec / 60
        let s = sec % 60
        return (String(format: "%d:%02d", m, s), nil)
    }
}

private struct DigitsRestCountdown: View {
    let endsAt: Date
    var useLarge: Bool = false

    var body: some View {
        RestTimelineCore(
            endsAt: endsAt,
            startedAt: nil,
            fallbackProgress: nil,
            showProgressBar: false,
            islandCompact: !useLarge
        )
    }
}

/// Shared rest UI: `TimelineView` + clamped remaining; native timer `ProgressView` when start/end known.
private struct RestTimelineCore: View {
    let endsAt: Date
    let startedAt: Date?
    let fallbackProgress: Double?
    let showProgressBar: Bool
    /// When true (compact island / minimal), keep type small unless we’re in the final 30s.
    let islandCompact: Bool

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 0.25)) { context in
            let rem = max(0, endsAt.timeIntervalSince(context.date))
            restContent(remaining: rem, now: context.date)
        }
    }

    @ViewBuilder
    private func restContent(remaining: TimeInterval, now: Date) -> some View {
        let (text, bigFont) = LiveActivityRestFormat.display(
            remaining: remaining,
            islandCompact: islandCompact
        )
        VStack(alignment: .leading, spacing: 4) {
            if showProgressBar {
                if let s = startedAt, s <= endsAt {
                    ProgressView(timerInterval: s ... endsAt, countsDown: true)
                        .progressViewStyle(.linear)
                        .tint(Color.blue.opacity(0.92))
                        .frame(height: 5)
                } else {
                    legacyProgressBar(remaining: remaining)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if showProgressBar {
                    Text("Rest")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Group {
                    if let bf = bigFont {
                        Text(text)
                            .font(bf)
                            .monospacedDigit()
                    } else if islandCompact {
                        Text(text)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                    } else {
                        Text(text)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
            }
        }
    }

    /// Progress bar when we lack `startedAt` (fallback to fraction from snapshot progress).
    private func legacyProgressBar(remaining: TimeInterval) -> some View {
        let rawRem = remaining
        let total: TimeInterval = {
            if let fp = fallbackProgress, fp > 0.001, rawRem > 0 {
                return max(0.001, rawRem / max(0.001, 1.0 - min(0.999, fp)))
            }
            return max(0.001, rawRem)
        }()
        let elapsed = max(0, total - rawRem)
        let fraction = min(1, max(0, elapsed / total))

        return GeometryReader { geo in
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
    }
}

private struct LockScreenRestBlock: View {
    let endsAt: Date?
    let startedAt: Date?
    let fallbackProgress: Double?

    var body: some View {
        Group {
            if let endsAt {
                RestTimelineCore(
                    endsAt: endsAt,
                    startedAt: startedAt,
                    fallbackProgress: fallbackProgress,
                    showProgressBar: true,
                    islandCompact: false
                )
            }
        }
    }
}
