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
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("This workout was left open for a while.")
                                .font(.title3.weight(.bold))
                                .multilineTextAlignment(.leading)
                            Text("Choose how you want to continue.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: 520, alignment: .leading)
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.ultraThinMaterial)
                        }

                        Text("Logged sets stay on this iPhone. Resume keeps training; Finish saves to Past workouts; Discard deletes this session.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 520, alignment: .leading)
                            .padding(.horizontal, 20)

                        VStack(spacing: 12) {
                            Button {
                                LoggyFeedback.primaryActionTap()
                                try? env.workouts.touchActiveState(sessionId: sessionId)
                                onDone()
                                dismiss()
                            } label: {
                                Text("Resume")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                try? env.workouts.finishSession(sessionId: sessionId)
                                LoggyFeedback.workoutFinishedSaved()
                                Task { @MainActor in
                                    await env.appleHealth.onWorkoutFinished(sessionId: sessionId)
                                    await env.liveActivity.end()
                                }
                                onDone()
                                dismiss()
                            } label: {
                                Text("Finish now")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(.bordered)

                            InlineConfirmButton(
                                action: {
                                    discardSessionAndDismiss()
                                },
                                idleLabel: {
                                    Text("Discard workout")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.red)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                },
                                armedLabel: {
                                    Text("Tap to confirm")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.red, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            )
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
            .navigationTitle("Recover workout")
            .navigationBarTitleDisplayMode(.inline)
            // Discard is now confirmed inline next to its trigger via `InlineConfirmButton`.
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

    private func discardSessionAndDismiss() {
        env.appleHealth.onWorkoutDiscarded(sessionId: sessionId)
        try? env.workouts.discardSession(sessionId: sessionId)
        LoggyFeedback.workoutDiscarded()
        Task { @MainActor in await env.liveActivity.end() }
        onDone()
        dismiss()
    }
}
