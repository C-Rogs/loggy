import SwiftUI

struct SessionRecoveryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

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
                        try? env.workouts.touchActiveState(sessionId: sessionId)
                        onDone()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Finish now") {
                        try? env.workouts.finishSession(sessionId: sessionId)
                        Task { @MainActor in await env.liveActivity.end() }
                        onDone()
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Discard", role: .destructive) {
                        try? env.workouts.discardSession(sessionId: sessionId)
                        Task { @MainActor in await env.liveActivity.end() }
                        onDone()
                        dismiss()
                    }
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Recover workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}
