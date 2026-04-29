import AppIntents
import Foundation

/// Lock screen / banner actions without opening the app (`openAppWhenRun = false`).
/// Per Apple: adopt `LiveActivityIntent` so `perform()` runs in the **host app process** (same database as the workout UI).
/// The widget extension compiles a stub `perform` body; only the main app target executes real work.
@available(iOS 17.0, *)
struct LoggyMarkSetDoneLiveIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Done"
    static var description = IntentDescription("Mark the current set complete.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Session ID") var sessionId: String
    @Parameter(title: "Session exercise ID") var sessionExerciseId: String
    @Parameter(title: "Set entry ID") var setEntryId: String

    init(sessionId: String, sessionExerciseId: String, setEntryId: String) {
        self.sessionId = sessionId
        self.sessionExerciseId = sessionExerciseId
        self.setEntryId = setEntryId
    }

    init() {
        sessionId = ""
        sessionExerciseId = ""
        setEntryId = ""
    }

    func perform() async throws -> some IntentResult {
        #if LOGGY_LIVE_ACTIVITY_EXTENSION
        return .result()
        #else
        let parsed = LoggyWorkoutDeepLink.Parsed(
            op: .complete,
            sessionId: sessionId,
            wse: sessionExerciseId,
            setId: setEntryId,
            delta: nil
        )
        await MainActor.run {
            guard let env = AppEnvironment.sharedOrCreateForLockScreenAction() else { return }
            env.handleWorkoutLiveParsed(parsed)
        }
        return .result()
        #endif
    }
}

@available(iOS 17.0, *)
struct LoggySkipRestLiveIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip rest"
    static var description = IntentDescription("End the rest timer early.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Session ID") var sessionId: String

    init(sessionId: String) {
        self.sessionId = sessionId
    }

    init() {
        sessionId = ""
    }

    func perform() async throws -> some IntentResult {
        #if LOGGY_LIVE_ACTIVITY_EXTENSION
        return .result()
        #else
        let parsed = LoggyWorkoutDeepLink.Parsed(
            op: .skipRest,
            sessionId: sessionId,
            wse: nil,
            setId: nil,
            delta: nil
        )
        await MainActor.run {
            guard let env = AppEnvironment.sharedOrCreateForLockScreenAction() else { return }
            env.handleWorkoutLiveParsed(parsed)
        }
        return .result()
        #endif
    }
}
