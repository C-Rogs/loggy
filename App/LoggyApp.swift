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
                } else {
                    Text("Could not open database.")
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
