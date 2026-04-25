import SwiftUI

struct ExerciseDirectoryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var vm = ExerciseDirectoryViewModel()

    @State private var newExerciseName: String = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("New custom exercise", text: $newExerciseName)
                    Button("Add") {
                        guard !newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        try? vm.createCustom(name: newExerciseName, env: env)
                        newExerciseName = ""
                    }
                }
            }

            Section("Exercises") {
                ForEach(vm.exercises) { ex in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ex.displayName).font(.headline)
                        Text(ex.exerciseMode.rawValue.replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Exercises")
        .searchable(text: $vm.query)
        .task { try? vm.refresh(env: env) }
        .onChange(of: vm.query) { _, _ in
            try? vm.refresh(env: env)
        }
    }
}
