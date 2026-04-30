import HealthKit
import SwiftUI
import WatchKit

/// Receives the same ``HKWorkoutConfiguration`` iPhone sent via ``HKHealthStore/startWatchApp(toHandle:)``.
private final class LoggyWatchApplicationDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            guard let coord = WatchSessionCoordinator.shared else { return }
            await coord.handleHealthKitWorkoutLaunch(configuration: workoutConfiguration)
        }
    }
}

@main
struct LoggyWatchApp: App {
    @WKApplicationDelegateAdaptor(LoggyWatchApplicationDelegate.self) private var watchDelegate

    @StateObject private var coordinator = WatchSessionCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
        }
    }
}
