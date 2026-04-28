import SwiftUI

struct ReplaceExerciseSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    let sessionExerciseId: String
    let currentExerciseId: String
    let exerciseMode: ExerciseMode
    let onPick: (String) -> Void

    @State private var query: String = ""
    @State private var suggestions: [ExerciseSummary] = []
    @State private var showFullCatalogue = false

    var body: some View {
        NavigationStack {
            Group {
                if trimmedQuery.isEmpty {
                    List {
                        if !suggestions.isEmpty {
                            Section {
                                ForEach(suggestions) { ex in
                                    pickRow(ex)
                                }
                            } header: {
                                Text("Similar movement")
                            }
                        } else {
                            ContentUnavailableView(
                                "No suggestions",
                                systemImage: "figure.strengthtraining.traditional",
                                description: Text("Try search below — same log type (\(modeLabel)) only.")
                            )
                        }
                    }
                } else {
                    List(filteredSearch) { ex in
                        pickRow(ex)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Replace exercise")
            .toolbarBackground(
                LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Browse all") {
                        showFullCatalogue = true
                    }
                }
            }
            .sheet(isPresented: $showFullCatalogue) {
                ExercisePickerSheet(
                    onPick: { picked in
                        guard picked != currentExerciseId else { return }
                        LoggyFeedback.primaryActionTap()
                        onPick(picked)
                        showFullCatalogue = false
                        dismiss()
                    },
                    lockedExerciseMode: exerciseMode
                )
                .environmentObject(env)
            }
            .task {
                suggestions = (try? env.exercises.replacementCandidates(forExerciseId: currentExerciseId, limit: 50)) ?? []
            }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredSearch: [ExerciseSummary] {
        let list = (try? env.exercises.searchExercises(query: trimmedQuery)) ?? []
        return list.filter { $0.id != currentExerciseId && $0.exerciseMode == exerciseMode }
    }

    private var modeLabel: String {
        switch exerciseMode {
        case .weightReps: return "weights + reps"
        case .bodyweightReps: return "bodyweight reps"
        case .duration: return "duration"
        case .distanceDuration: return "distance / time"
        }
    }

    @ViewBuilder
    private func pickRow(_ ex: ExerciseSummary) -> some View {
        Button {
            LoggyFeedback.primaryActionTap()
            onPick(ex.id)
            dismiss()
        } label: {
            Text(ex.displayName)
                .foregroundStyle(.primary)
        }
    }
}
