import Foundation

@MainActor
final class ExerciseDirectoryViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var exercises: [ExerciseSummary] = []

    func refresh(env: AppEnvironment) throws {
        exercises = try env.exercises.searchExercises(query: query)
    }

    func createCustom(name: String, env: AppEnvironment) throws {
        _ = try env.exercises.createCustomExercise(displayName: name, mode: .weightReps)
        try refresh(env: env)
    }
}
