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

            MuscleFilterChipBar(selection: $vm.muscleSlugFilter)

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
                if vm.exercises.isEmpty {
                    ContentUnavailableView(
                        "No exercises",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Try another search, type filter, or clear the muscle chip.")
                    )
                } else {
                    ForEach(vm.exercises) { ex in
                        NavigationLink {
                            ExerciseInfoView(exerciseId: ex.id)
                        } label: {
                            ExerciseSummaryRowLabel(exercise: ex, style: .directory)
                                .padding(.vertical, 4)
                        }
                    }
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
        .task { try? vm.refreshImmediately(env: env) }
        .onChange(of: vm.query) { _, _ in
            vm.scheduleSearchRefresh(env: env)
        }
        .onChange(of: vm.modeFilter) { _, _ in
            try? vm.refreshImmediately(env: env)
        }
        .onChange(of: vm.muscleSlugFilter) { _, _ in
            try? vm.refreshImmediately(env: env)
        }
    }
}
