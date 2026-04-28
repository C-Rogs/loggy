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

    init(onPick: @escaping (String) -> Void) {
        mode = .single(onPick: onPick)
    }

    init(onPickMany: @escaping ([String]) -> Void) {
        mode = .multi(onPickMany: onPickMany)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Group {
                    switch mode {
                    case .single:
                        List(vm.exercises) { ex in
                            Button(ex.displayName) {
                                if case let .single(onPick) = mode {
                                    LoggyFeedback.primaryActionTap()
                                    onPick(ex.id)
                                    dismiss()
                                }
                            }
                        }
                    case .multi:
                        List(vm.exercises) { ex in
                            let isOn = selectedIds.contains(ex.id)
                            HStack(spacing: 12) {
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                                Text(ex.displayName)
                                    .foregroundStyle(.primary)
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
            .task { try? vm.refresh(env: env) }
            .onChange(of: vm.query) { _, _ in
                try? vm.refresh(env: env)
            }
            .onChange(of: vm.modeFilter) { _, _ in
                try? vm.refresh(env: env)
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
