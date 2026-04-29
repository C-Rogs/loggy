import SwiftUI

@main
struct LoggyWatchApp: App {
    @StateObject private var coordinator = WatchSessionCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
        }
    }
}
