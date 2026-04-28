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
    @Published private(set) var exercises: [ExerciseSummary] = []

    func refresh(env: AppEnvironment) throws {
        var list = try env.exercises.searchExercises(query: query)
        if let mode = modeFilter.exerciseMode {
            list = list.filter { $0.exerciseMode == mode }
        }
        exercises = list
    }

    func createCustom(name: String, env: AppEnvironment) throws {
        _ = try env.exercises.createCustomExercise(displayName: name, mode: .weightReps)
        try refresh(env: env)
    }
}
