import Foundation

@MainActor
final class TemplatesViewModel: ObservableObject {
    @Published private(set) var templates: [WorkoutTemplateSummary] = []

    func refresh(env: AppEnvironment) throws {
        templates = try env.templates.listTemplates()
    }

    func create(name: String, env: AppEnvironment) throws {
        _ = try env.templates.createTemplate(name: name)
        try refresh(env: env)
    }

    func delete(id: String, env: AppEnvironment) throws {
        try env.templates.deleteTemplate(id: id)
        try refresh(env: env)
    }

    func addExercise(templateId: String, exerciseId: String, env: AppEnvironment) throws {
        try env.templates.addExerciseToTemplate(templateId: templateId, exerciseId: exerciseId)
        try refresh(env: env)
    }
}
