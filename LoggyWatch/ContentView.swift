import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var coordinator: WatchSessionCoordinator

    var body: some View {
        Group {
            if let snap = coordinator.snapshot, snap.phase == .active {
                ActiveWorkoutMirrorView(
                    snapshot: snap,
                    bpm: coordinator.liveHeartRateBpm,
                    bpmAt: coordinator.liveHeartRateMeasuredAt
                )
            } else {
                IdlePromptView()
            }
        }
    }
}

private struct IdlePromptView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "applewatch")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("Start a workout in Loggy on iPhone")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .padding(.horizontal)
        }
        .padding()
    }
}

private struct ActiveWorkoutMirrorView: View {
    let snapshot: WatchActiveWorkoutSnapshot
    let bpm: Int?
    let bpmAt: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                exerciseHeader
                elapsedRow
                attentionBanner
                nextSetBlock
                restBlock
                Divider().opacity(0.2)
                healthRow
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            // Subtle / private — the rest of the gym shouldn't be able to read this.
            .opacity(0.62)
        }
    }

    /// Shown briefly after a rest naturally completes (`restAttentionExpiresAt`) so the user sees a clear "GO" cue without having to look at the phone. Mirrors the iPhone Live Activity attention window.
    @ViewBuilder
    private var attentionBanner: some View {
        if let attStr = snapshot.restAttentionExpiresAt,
           let expires = ISO8601UTC.date(from: attStr)
        {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                if ctx.date < expires {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.and.waves.left.and.right.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("Start your next set")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                        Spacer(minLength: 0)
                        Text("GO")
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private var exerciseHeader: some View {
        Text(snapshot.currentExerciseName.isEmpty ? "Workout" : snapshot.currentExerciseName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
    }

    @ViewBuilder
    private var elapsedRow: some View {
        if let startStr = snapshot.workoutStartedAt,
           let started = ISO8601UTC.date(from: startStr)
        {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let sec = LiveActivityElapsedLogic.elapsedDisplaySeconds(
                    now: ctx.date,
                    workoutStartedAt: started,
                    fallbackElapsedSeconds: 0
                )
                HStack(spacing: 6) {
                    Text(formatElapsed(sec))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("\(snapshot.completedSetCount) sets")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var nextSetBlock: some View {
        if !snapshot.currentSetTitle.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(snapshot.currentSetTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(snapshot.currentSetWeightDisplay)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text("×")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(snapshot.currentSetRepsDisplay)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                if let preview = snapshot.nextSetPreview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var restBlock: some View {
        if let restEndStr = snapshot.restEndsAt,
           let restEnd = ISO8601UTC.date(from: restEndStr)
        {
            // Suppress the rest countdown while the post-rest attention banner is visible so we never show "Rest" + "GO" simultaneously.
            let attentionExpires = snapshot.restAttentionExpiresAt.flatMap(ISO8601UTC.date(from:))
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let rem = max(0, restEnd.timeIntervalSince(ctx.date))
                let sec = Int(ceil(rem))
                let attentionActive = attentionExpires.map { ctx.date < $0 } ?? false
                if sec > 0, !attentionActive {
                    HStack(spacing: 6) {
                        Text("Rest")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text("\(sec)s")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var healthRow: some View {
        if snapshot.healthSyncEnabled {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.pink.opacity(0.85))
                if let bpm {
                    Text("\(bpm)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text("bpm")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let bpmAt {
                        StaleBpmHint(measuredAt: bpmAt)
                    }
                } else {
                    Text("—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Dot turns dim if the last sample is older than ~10 s (`HKLiveWorkoutBuilder` typically delivers ~1 Hz when the wrist is detected).
private struct StaleBpmHint: View {
    let measuredAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { ctx in
            let age = ctx.date.timeIntervalSince(measuredAt)
            Circle()
                .fill(age < 10 ? Color.green : Color.gray)
                .frame(width: 5, height: 5)
                .opacity(0.7)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchSessionCoordinator())
}
