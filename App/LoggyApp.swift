import SwiftUI
import os.log

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
                            "Free space is only one possible cause—check the technical detail below for the SQLite code. IO errors can also mean a partial or corrupted local database after an interrupted install."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        if let detail = environment.initializationError, !detail.isEmpty {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal)
                                .textSelection(.enabled)
                        }
                        Button("Try again") {
                            environment.retry()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Reset Loggy data & retry…", role: .destructive) {
                            environment.showResetConfirmation = true
                        }
                    }
                    .padding()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Loggy couldn’t open its database. Try freeing storage, restarting the device, or reinstalling the app."
                    )
                    .alert("Reset all Loggy data?", isPresented: $environment.showResetConfirmation) {
                        Button("Cancel", role: .cancel) {}
                        Button("Delete & retry", role: .destructive) {
                            environment.resetDatabaseAndRetry()
                        }
                    } message: {
                        Text(
                            "Removes every workout, template, and log stored in Loggy on this iPhone. This cannot be undone. Use this if the SQLite error suggests a damaged local database (e.g. after a failed migration)."
                        )
                    }
                }
            }
        }
    }
}

@MainActor
private final class AppEnvironmentWrapper: ObservableObject {
    @Published var value: AppEnvironment?
    @Published var initializationError: String?
    @Published var showResetConfirmation = false

    init() {
        attemptSetup()
    }

    func retry() {
        attemptSetup()
    }

    func resetDatabaseAndRetry() {
        do {
            try AppDatabase.removeSharedDatabaseStoreForRecovery()
            attemptSetup()
        } catch {
            value = nil
            AppEnvironment.clearSharedInstance()
            initializationError = LoggyDatabaseStartupDiagnostics.formattedMessage(for: error)
        }
    }

    private func attemptSetup() {
        initializationError = nil
        AppEnvironment.clearSharedInstance()
        do {
            let env = try AppEnvironment()
            value = env
            AppEnvironment.registerSharedInstance(env)
            initializationError = nil
            Logger.startup.info("AppEnvironment ready")
        } catch {
            value = nil
            AppEnvironment.clearSharedInstance()
            let msg = LoggyDatabaseStartupDiagnostics.formattedMessage(for: error)
            initializationError = msg
            Logger.startup.error("AppEnvironment failed: \(msg, privacy: .public)")
        }
    }
}
