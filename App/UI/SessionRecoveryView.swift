import SwiftUI

struct SessionRecoveryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    let sessionId: String
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("This workout was left open for a while.")
                    .font(.headline)

                Text("Choose how you want to continue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Button("Resume") {
                        LoggyFeedback.primaryActionTap()
                        try? env.workouts.touchActiveState(sessionId: sessionId)
                        onDone()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Finish now") {
                        try? env.workouts.finishSession(sessionId: sessionId)
                        LoggyFeedback.workoutFinishedSaved()
                        Task { @MainActor in
                            await env.appleHealth.onWorkoutFinished(sessionId: sessionId)
                            await env.liveActivity.end()
                        }
                        onDone()
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Discard", role: .destructive) {
                        env.appleHealth.onWorkoutDiscarded(sessionId: sessionId)
                        try? env.workouts.discardSession(sessionId: sessionId)
                        LoggyFeedback.workoutDiscarded()
                        Task { @MainActor in await env.liveActivity.end() }
                        onDone()
                        dismiss()
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
            .navigationTitle("Recover workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(
                LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
