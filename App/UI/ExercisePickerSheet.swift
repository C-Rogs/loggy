import SwiftUI

struct ExercisePickerSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    @StateObject private var vm = ExerciseDirectoryViewModel()
    @State private var selectedIds: Set<String> = []

    private enum Mode {
        case single(onPick: (String) -> Void)
        case multi(onPickMany: ([String]) -> Void)
    }

    private let mode: Mode
    /// When set, the segmented mode control is fixed to this log type (e.g. replace-exercise slot).
    private let lockedExerciseMode: ExerciseMode?

    init(onPick: @escaping (String) -> Void, lockedExerciseMode: ExerciseMode? = nil) {
        mode = .single(onPick: onPick)
        self.lockedExerciseMode = lockedExerciseMode
    }

    init(onPickMany: @escaping ([String]) -> Void) {
        mode = .multi(onPickMany: onPickMany)
        lockedExerciseMode = nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Type", selection: $vm.modeFilter) {
                    ForEach(ExercisePickerModeFilter.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(lockedExerciseMode != nil)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                MuscleFilterChipBar(selection: $vm.muscleSlugFilter)

                Group {
                    switch mode {
                    case .single:
                        List {
                            if vm.exercises.isEmpty {
                                ContentUnavailableView(
                                    "No exercises",
                                    systemImage: "figure.run",
                                    description: Text("Adjust search, type, or muscle filter.")
                                )
                                .listRowBackground(Color.clear)
                            } else {
                                ForEach(vm.exercises) { ex in
                                    Button {
                                        if case let .single(onPick) = mode {
                                            LoggyFeedback.primaryActionTap()
                                            onPick(ex.id)
                                            dismiss()
                                        }
                                    } label: {
                                        ExerciseSummaryRowLabel(exercise: ex, style: .list)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    case .multi:
                        List {
                            if vm.exercises.isEmpty {
                                ContentUnavailableView(
                                    "No exercises",
                                    systemImage: "figure.run",
                                    description: Text("Adjust search, type, or muscle filter.")
                                )
                                .listRowBackground(Color.clear)
                            } else {
                                ForEach(vm.exercises) { ex in
                                    let isOn = selectedIds.contains(ex.id)
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isOn ? Color.accentColor : .secondary)
                                            .padding(.top, 2)
                                        ExerciseSummaryRowLabel(exercise: ex, style: .list)
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if selectedIds.contains(ex.id) {
                                            selectedIds.remove(ex.id)
                                        } else {
                                            selectedIds.insert(ex.id)
                                            LoggyFeedback.listSelectionTap()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
            }
            .searchable(text: $vm.query)
            .navigationTitle(modeTitle)
            .toolbarBackground(
                LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if case .multi = mode {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add (\(selectedIds.count))") {
                            if case let .multi(onPickMany) = mode {
                                LoggyFeedback.primaryActionTap()
                                onPickMany(Array(selectedIds))
                                dismiss()
                            }
                        }
                        .disabled(selectedIds.isEmpty)
                    }
                }
            }
            .task {
                if let m = lockedExerciseMode {
                    vm.modeFilter = ExercisePickerModeFilter.forLockedExerciseMode(m)
                }
                try? vm.refreshImmediately(env: env)
            }
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

    private var modeTitle: String {
        switch mode {
        case .single: return "Pick exercise"
        case .multi: return "Add exercises"
        }
    }
}
