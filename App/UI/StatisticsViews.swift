import SwiftUI

struct StatisticsHubView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    var body: some View {
        List {
            Section {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(height: 140)
                    .overlay {
                        Text("Muscle overview")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
                    StatisticsPlaceholderView(
                        title: "Muscle distribution (Chart)",
                        message: "Compare current and previous muscle distributions — coming soon."
                    )
                } label: {
                    advancedRow(
                        title: "Muscle distribution (Chart)",
                        subtitle: "Compare your current and previous muscle distributions.",
                        systemImage: "pentagon"
                    )
                }
                NavigationLink {
                    StatisticsPlaceholderView(
                        title: "Muscle distribution (Body)",
                        message: "Weekly heat map of muscles worked — coming soon."
                    )
                } label: {
                    advancedRow(
                        title: "Muscle distribution (Body)",
                        subtitle: "Weekly heat map of muscles worked.",
                        systemImage: "figure.stand"
                    )
                }
                NavigationLink {
                    StatisticsPlaceholderView(
                        title: "Main exercises",
                        message: "Most frequent exercises — coming soon."
                    )
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
                    Text("No completed sets with muscle metadata in this range.")
                        .foregroundStyle(.secondary)
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
        .task { reload() }
    }

    private func reload() {
        rows = (try? env.workouts.completedSetCountsByPrimaryMuscle(sinceDaysAgo: window.sinceDays)) ?? []
    }
}

struct StatisticsPlaceholderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView(message, systemImage: "chart.xyaxis.line")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
    }
}
