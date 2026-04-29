import SwiftUI

struct ReplaceExerciseSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    let currentExerciseId: String
    let exerciseMode: ExerciseMode
    let onPick: (String) -> Void

    @State private var query: String = ""
    @State private var suggestions: [ExerciseSummary] = []
    /// Populated after debounced search (avoids SQLite work every keystroke).
    @State private var searchMatches: [ExerciseSummary] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var isSearchLoading = false
    @State private var showFullCatalogue = false
    /// Filters both “Similar movement” suggestions and search results.
    @State private var muscleSlugFilter: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MuscleFilterChipBar(selection: $muscleSlugFilter)

                Group {
                    if trimmedQuery.isEmpty {
                        List {
                            if !displayedSuggestions.isEmpty {
                                Section {
                                    ForEach(displayedSuggestions) { ex in
                                        pickRow(ex)
                                    }
                                } header: {
                                    Text("Similar movement")
                                }
                            } else {
                                ContentUnavailableView(
                                    suggestions.isEmpty ? "No suggestions" : "No matches",
                                    systemImage: "figure.strengthtraining.traditional",
                                    description: suggestionsEmptyDescription
                                )
                            }
                        }
                    } else if isSearchLoading && searchMatches.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 40)
                    } else if searchMatches.isEmpty {
                        ContentUnavailableView(
                            "No matches",
                            systemImage: "magnifyingglass",
                            description: Text("Try different words, clear the muscle filter, or browse all.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(searchMatches) { ex in
                            pickRow(ex)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
            }
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
            .onChange(of: query) { _, _ in
                scheduleSearchLoad(env: env)
            }
            .onChange(of: muscleSlugFilter) { _, _ in
                reloadSearchIfNeeded(env: env)
            }
            .onDisappear {
                searchDebounceTask?.cancel()
            }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Suggestions when search field is empty; narrowed by muscle chip when set.
    private var displayedSuggestions: [ExerciseSummary] {
        guard let slug = muscleSlugFilter?.trimmingCharacters(in: .whitespacesAndNewlines), !slug.isEmpty else {
            return suggestions
        }
        return suggestions.filter { ex in
            guard let p = ex.primaryMuscleGroup?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else {
                return false
            }
            return p.compare(slug, options: .caseInsensitive) == .orderedSame
        }
    }

    private func scheduleSearchLoad(env: AppEnvironment) {
        let q = trimmedQuery
        if q.isEmpty {
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
            searchMatches = []
            isSearchLoading = false
            return
        }
        isSearchLoading = true
        MainActorDebouncer.reschedule(&searchDebounceTask) {
            self.runSearchQuery(env: env)
        }
    }

    private func reloadSearchIfNeeded(env: AppEnvironment) {
        guard !trimmedQuery.isEmpty else { return }
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        isSearchLoading = true
        runSearchQuery(env: env)
    }

    private func runSearchQuery(env: AppEnvironment) {
        let q = trimmedQuery
        guard !q.isEmpty else {
            searchMatches = []
            isSearchLoading = false
            return
        }
        let list = (try? env.exercises.searchExercises(
            query: q,
            primaryMuscleSlug: muscleSlugFilter,
            exerciseMode: exerciseMode
        )) ?? []
        searchMatches = list.filter { $0.id != currentExerciseId }
        isSearchLoading = false
    }

    private var suggestionsEmptyDescription: Text {
        if suggestions.isEmpty {
            return Text("Try search below — same log type (\(modeLabel)) only.")
        }
        if muscleSlugFilter != nil {
            return Text("Nothing in this muscle — clear the chip or try search.")
        }
        return Text("Try search below — same log type (\(modeLabel)) only.")
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
            ExerciseSummaryRowLabel(exercise: ex, style: .list)
        }
        .buttonStyle(.plain)
    }
}
