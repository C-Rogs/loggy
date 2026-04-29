import SwiftUI

@main
struct LoggyApp: App {
    @StateObject private var environment: AppEnvironmentWrapper = AppEnvironmentWrapper()

    var body: some Scene {
        WindowGroup {
            Group {
                if let env = environment.value {
                    RootView()
                        .environmentObject(env)
                        .onOpenURL { env.handleWorkoutLiveURL($0) }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Loggy couldn’t open its database")
                            .font(.headline)
                        Text(
                            "Try freeing storage, restarting the device, or reinstalling the app. If the problem continues, your device may need more free space."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    }
                    .padding()
                }
            }
        }
    }
}

@MainActor
private final class AppEnvironmentWrapper: ObservableObject {
    @Published var value: AppEnvironment?

    init() {
        self.value = try? AppEnvironment()
    }
}
