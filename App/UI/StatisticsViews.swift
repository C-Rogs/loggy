import Charts
import SwiftUI

// MARK: - Hub

struct StatisticsHubView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    @State private var topMuscles: [MuscleGroupSetCount] = []

    var body: some View {
        List {
            Section {
                if topMuscles.isEmpty {
                    ContentUnavailableView(
                        "No stats yet",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Complete workouts with muscle metadata to see your top muscles here.")
                    )
                    .listRowInsets(EdgeInsets(top: 24, leading: 0, bottom: 24, trailing: 0))
                    .listRowBackground(Color.clear)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Last 30 days — top muscles by sets")
                            .font(.subheadline.weight(.semibold))
                        ForEach(topMuscles.prefix(5)) { m in
                            HStack {
                                Text(m.displayLabel)
                                Spacer()
                                Text("\(m.completedSetCount)")
                                    .font(.body.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                        NavigationLink("View body map") {
                            BodyMapStatsView()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 6)
                }
            } header: {
                Text("Statistics")
            }

            Section {
                Text("Advanced statistics")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                NavigationLink {
                    SetCountPerMuscleGroupView()
                } label: {
                    advancedRow(
                        title: "Set count per muscle group",
                        subtitle: "Number of sets logged for each muscle group.",
                        systemImage: "chart.bar.xaxis"
                    )
                }
                NavigationLink {
                    MuscleDistributionChartView()
                } label: {
                    advancedRow(
                        title: "Muscle distribution (Chart)",
                        subtitle: "Compare your current and previous muscle distributions.",
                        systemImage: "pentagon"
                    )
                }
                NavigationLink {
                    BodyMapStatsView()
                } label: {
                    advancedRow(
                        title: "Muscle distribution (Body)",
                        subtitle: "Weekly heat map of muscles worked.",
                        systemImage: "figure.stand"
                    )
                }
                NavigationLink {
                    WorkoutContributionHeatmapView()
                } label: {
                    advancedRow(
                        title: "Workout streak",
                        subtitle: "GitHub-style 26-week grid blended with average RPE.",
                        systemImage: "calendar"
                    )
                }
                NavigationLink {
                    MainExercisesView()
                } label: {
                    advancedRow(
                        title: "Main exercises",
                        subtitle: "List of exercises you do most often.",
                        systemImage: "dumbbell"
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(
            LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            await refreshHub()
        }
        .task {
            await refreshHub()
        }
    }

    private func refreshHub() async {
        let rows = (try? env.workouts.completedSetCountsByPrimaryMuscle(sinceDaysAgo: 30)) ?? []
        topMuscles = rows.sorted { $0.completedSetCount > $1.completedSetCount }
    }

    private func advancedRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Set count per muscle (existing screen)

struct SetCountPerMuscleGroupView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    enum Window: String, CaseIterable, Identifiable {
        case last30 = "Last 30 days"
        case year = "Year"
        case all = "All time"

        var id: String { rawValue }

        var sinceDays: Int? {
            switch self {
            case .last30: return 30
            case .year: return 365
            case .all: return nil
            }
        }
    }

    @State private var window: Window = .last30
    @State private var rows: [MuscleGroupSetCount] = []

    var body: some View {
        List {
            Section {
                Picker("Window", selection: $window) {
                    ForEach(Window.allCases) { w in
                        Text(w.rawValue).tag(w)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: window) { _, _ in reload() }
            }
            if rows.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No data in this range",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("No completed sets with muscle metadata for the selected window.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(rows) { r in
                        HStack {
                            Text(r.displayLabel)
                            Spacer()
                            Text("\(r.completedSetCount)")
                                .font(.body.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Sets by primary muscle")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        .navigationTitle("Set count per muscle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            await MainActor.run { reload() }
        }
        .task { reload() }
    }

    private func reload() {
        rows = (try? env.workouts.completedSetCountsByPrimaryMuscle(sinceDaysAgo: window.sinceDays)) ?? []
    }
}

// MARK: - Muscle distribution chart (current vs previous rolling windows)

/// Compares completed sets aggregated to coarse muscle buckets: **last `windowDays`** vs **prior `windowDays`** (same length immediately before).
struct MuscleDistributionChartView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    @State private var rows: [MuscleCoarseDistributionRow] = []
    @State private var windowDays: Int = 30

    var body: some View {
        List {
            Section {
                Picker("Window length", selection: $windowDays) {
                    Text("30 days").tag(30)
                    Text("14 days").tag(14)
                    Text("7 days").tag(7)
                }
                .pickerStyle(.segmented)
                .onChange(of: windowDays) { _, _ in reload() }
                Text(
                    "Bars show completed sets per coarse muscle group. “Last” is the most recent window; “Prior” is the same number of days immediately before."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if rows.allSatisfy({ $0.currentSetCount + $0.previousSetCount == 0 }) {
                Section {
                    ContentUnavailableView(
                        "No distribution yet",
                        systemImage: "pentagon",
                        description: Text("Complete sets in back-to-back windows to compare muscle balance.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    Text("Last \(windowDays) days")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Chart {
                        ForEach(rows.filter { $0.currentSetCount > 0 }) { r in
                            BarMark(
                                x: .value("Sets", r.currentSetCount),
                                y: .value("Muscle", r.title)
                            )
                            .foregroundStyle(Color.accentColor.opacity(0.9))
                        }
                    }
                    .chartXAxisLabel("Completed sets")
                    .frame(height: CGFloat(max(160, rows.filter { $0.currentSetCount > 0 }.count * 28)))
                }
                Section {
                    Text("Prior \(windowDays) days")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Chart {
                        ForEach(rows.filter { $0.previousSetCount > 0 }) { r in
                            BarMark(
                                x: .value("Sets", r.previousSetCount),
                                y: .value("Muscle", r.title)
                            )
                            .foregroundStyle(Color.orange.opacity(0.85))
                        }
                    }
                    .chartXAxisLabel("Completed sets")
                    .frame(height: CGFloat(max(160, rows.filter { $0.previousSetCount > 0 }.count * 28)))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        .navigationTitle("Muscle distribution")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            await MainActor.run { reload() }
        }
        .task { reload() }
    }

    private func reload() {
        rows = (try? env.workouts.muscleDistributionCoarseCurrentVsPrevious(windowDays: windowDays)) ?? []
    }
}

// MARK: - Weekly muscle breakdown (“body” heat list)

struct MuscleDistributionBodyView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    @State private var weeks: [WeeklyMuscleSetRow] = []

    var body: some View {
        List {
            if weeks.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No weekly data",
                        systemImage: "calendar",
                        description: Text("Complete workouts to see sets grouped by week.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(weeks) { week in
                    Section {
                        ForEach(week.muscles.prefix(12)) { m in
                            HStack {
                                Text(m.displayLabel)
                                Spacer()
                                Text("\(m.completedSetCount)")
                                    .font(.body.monospacedDigit().weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        HStack {
                            Text("Week \(week.weekKey)")
                            Spacer()
                            Text(week.sortDateLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        .navigationTitle("Muscle by week")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            await MainActor.run { reloadWeeks() }
        }
        .task {
            reloadWeeks()
        }
    }

    private func reloadWeeks() {
        weeks = (try? env.workouts.weeklyMuscleSetRows(limitWeeks: 12)) ?? []
    }
}

// MARK: - Main exercises

struct MainExercisesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    enum Window: String, CaseIterable, Identifiable {
        case last30 = "Last 30 days"
        case year = "Year"
        case all = "All time"

        var id: String { rawValue }

        var sinceDays: Int? {
            switch self {
            case .last30: return 30
            case .year: return 365
            case .all: return nil
            }
        }
    }

    @State private var window: Window = .last30
    @State private var rows: [ExerciseSetFrequencyRow] = []

    var body: some View {
        List {
            Section {
                Picker("Window", selection: $window) {
                    ForEach(Window.allCases) { w in
                        Text(w.rawValue).tag(w)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: window) { _, _ in reload() }
            }
            if rows.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No exercises yet",
                        systemImage: "dumbbell",
                        description: Text("No completed sets in this time range. Log workouts to see frequency here.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(rows) { r in
                        NavigationLink {
                            ExerciseInfoView(exerciseId: r.exerciseId)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(r.displayName)
                                        .font(.body.weight(.semibold))
                                    Text("\(r.completedSetCount) sets")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        .navigationTitle("Main exercises")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            await MainActor.run { reload() }
        }
        .task { reload() }
    }

    private func reload() {
        rows =
            (try? env.workouts.exerciseSetFrequency(
                fromDaysAgo: window.sinceDays,
                toDaysAgo: nil,
                limit: 100
            )) ?? []
    }
}
