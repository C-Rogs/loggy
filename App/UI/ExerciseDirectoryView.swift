import SwiftUI

struct ExerciseDirectoryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark
    @StateObject private var vm = ExerciseDirectoryViewModel()

    @State private var newExerciseName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("Type", selection: $vm.modeFilter) {
                ForEach(ExercisePickerModeFilter.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

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
        }
        .scrollContentBackground(.hidden)
        .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        .navigationTitle("Exercises")
        .toolbarBackground(
            LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .searchable(text: $vm.query)
        .task { try? vm.refresh(env: env) }
        .onChange(of: vm.query) { _, _ in
            try? vm.refresh(env: env)
        }
        .onChange(of: vm.modeFilter) { _, _ in
            try? vm.refresh(env: env)
        }
    }
}
