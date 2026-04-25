import SwiftUI

struct TemplatesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var vm = TemplatesViewModel()

    @State private var newName: String = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("New template name", text: $newName)
                    Button("Create") {
                        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        try? vm.create(name: newName, env: env)
                        newName = ""
                    }
                }
            }

            Section("Templates") {
                ForEach(vm.templates) { t in
                    NavigationLink(t.name) {
                        TemplateDetailView(templateId: t.id)
                            .environmentObject(env)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            try? vm.delete(id: t.id, env: env)
                        } label: {
                            Text("Delete")
                        }
                    }
                }
            }
        }
        .navigationTitle("Templates")
        .task { try? vm.refresh(env: env) }
    }
}

private struct TemplateDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var vm = TemplatesViewModel()

    let templateId: String
    @State private var showPicker = false
    @State private var exercises: [ExerciseSummary] = []

    var body: some View {
        List {
            Section {
                Button("Start workout from this template") {
                    _ = try? env.workouts.startSessionFromTemplate(templateId: templateId, title: nil)
                }

                Button("Add exercise…") { showPicker = true }
            }

            Section("Exercises") {
                ForEach(exercises) { ex in
                    Text(ex.displayName)
                }
            }
        }
        .navigationTitle("Template")
        .sheet(isPresented: $showPicker) {
            ExercisePickerSheet { exerciseId in
                try? vm.addExercise(templateId: templateId, exerciseId: exerciseId, env: env)
                showPicker = false
                reloadExercises()
            }
            .environmentObject(env)
        }
        .task {
            try? vm.refresh(env: env)
            reloadExercises()
        }
    }

    private func reloadExercises() {
        exercises = (try? env.templates.listTemplateExercises(templateId: templateId)) ?? []
    }
}
