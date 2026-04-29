import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var coordinator: WatchSessionCoordinator

    var body: some View {
        Group {
            if let snap = coordinator.snapshot, snap.phase == .active {
                ActiveWorkoutMirrorView(snapshot: snap)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "applewatch")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Start a workout in Loggy on iPhone")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                .padding()
            }
        }
    }
}

private struct ActiveWorkoutMirrorView: View {
    let snapshot: WatchActiveWorkoutSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(snapshot.currentExerciseName)
                    .font(.headline.weight(.bold))
                    .minimumScaleFactor(0.8)

                if let startStr = snapshot.workoutStartedAt,
                   let started = ISO8601UTC.date(from: startStr)
                {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let sec = LiveActivityElapsedLogic.elapsedDisplaySeconds(
                            now: ctx.date,
                            workoutStartedAt: started,
                            fallbackElapsedSeconds: 0
                        )
                        Text(formatElapsed(sec))
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(snapshot.completedSetCount) sets")
                        .font(.caption.weight(.medium))
                }

                if let restEndStr = snapshot.restEndsAt,
                   let restEnd = ISO8601UTC.date(from: restEndStr)
                {
                    TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                        let rem = max(0, restEnd.timeIntervalSince(ctx.date))
                        let sec = Int(ceil(rem))
                        if sec > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Rest")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("\(sec)s")
                                    .font(.title2.weight(.bold).monospacedDigit())
                            }
                        }
                    }
                }

                if snapshot.healthSyncEnabled {
                    Label("Health sync on iPhone", systemImage: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                }
            }
            .padding()
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchSessionCoordinator())
}
