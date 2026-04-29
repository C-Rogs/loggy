import Foundation

enum ExercisePickerModeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case weightReps = "Weights"
    case bodyweightReps = "Bodyweight"
    case duration = "Time"
    case distanceDuration = "Distance"

    var id: String { rawValue }

    /// Picker segment matching a session slot’s log type (used when replacing an exercise).
    static func forLockedExerciseMode(_ mode: ExerciseMode) -> ExercisePickerModeFilter {
        switch mode {
        case .weightReps: return .weightReps
        case .bodyweightReps: return .bodyweightReps
        case .duration: return .duration
        case .distanceDuration: return .distanceDuration
        }
    }

    var exerciseMode: ExerciseMode? {
        switch self {
        case .all: nil
        case .weightReps: .weightReps
        case .bodyweightReps: .bodyweightReps
        case .duration: .duration
        case .distanceDuration: .distanceDuration
        }
    }
}

@MainActor
final class ExerciseDirectoryViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var modeFilter: ExercisePickerModeFilter = .all
    /// `primary_muscle_group` slug, or `nil` for all muscles.
    @Published var muscleSlugFilter: String?
    @Published private(set) var exercises: [ExerciseSummary] = []

    private var searchRefreshTask: Task<Void, Never>?

    deinit {
        searchRefreshTask?.cancel()
    }

    /// Runs the current filters immediately (cancels any pending search debounce).
    func refreshImmediately(env: AppEnvironment) throws {
        searchRefreshTask?.cancel()
        searchRefreshTask = nil
        try refresh(env: env)
    }

    /// Debounces DB work while the user is typing in the search field (~280ms).
    func scheduleSearchRefresh(env: AppEnvironment) {
        MainActorDebouncer.reschedule(&searchRefreshTask) {
            try? self.refresh(env: env)
        }
    }

    func refresh(env: AppEnvironment) throws {
        let list = try env.exercises.searchExercises(
            query: query,
            primaryMuscleSlug: muscleSlugFilter,
            exerciseMode: modeFilter.exerciseMode
        )
        exercises = list
    }

    func createCustom(name: String, env: AppEnvironment) throws {
        _ = try env.exercises.createCustomExercise(displayName: name, mode: .weightReps)
        try refreshImmediately(env: env)
    }
}
