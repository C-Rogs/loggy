import Charts
import SwiftUI

struct ExerciseHowToSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark
    let exerciseId: String

    @State private var info: ExerciseHowToInfo?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let urlStr = info?.gifURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(maxWidth: .infinity, minHeight: 180)
                            case let .success(image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 260)
                                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.materialCornerRadius, style: .continuous))
                            case .failure:
                                ContentUnavailableView("Could not load image", systemImage: "photo")
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    if let t = info?.instructionText, !t.isEmpty {
                        Text(t)
                            .font(.body)
                    } else {
                        Text("No written instructions yet.")
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        ExerciseAnalyticsView(exerciseId: exerciseId)
                    } label: {
                        Label("View history & charts", systemImage: "chart.xyaxis.line")
                            .font(.headline)
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
            .navigationTitle(info?.displayName ?? "Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(
                LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                info = try? env.exercises.exerciseHowTo(exerciseId: exerciseId)
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
}

struct ExerciseAnalyticsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark
    let exerciseId: String

    @State private var points: [ExerciseWeeklyStatPoint] = []
    @State private var title: String = "Exercise"

    var body: some View {
        List {
            if points.isEmpty {
                Section {
                    Text("Complete workouts with this exercise to see trends.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Chart(points) { p in
                        BarMark(
                            x: .value("Week", p.weekKey),
                            y: .value("Volume", p.volumeKg)
                        )
                        .foregroundStyle(.blue.gradient)
                    }
                    .frame(height: 220)
                } header: {
                    Text("Weekly volume (kg × reps summed)")
                }

                Section {
                    let maxPts = points.filter { ($0.maxWeightKg ?? 0) > 0 }
                    if maxPts.isEmpty {
                        Text("No max-weight data for these weeks.")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(maxPts) { p in
                            LineMark(
                                x: .value("Week", p.weekKey),
                                y: .value("Max kg", p.maxWeightKg ?? 0)
                            )
                            .interpolationMethod(.catmullRom)
                        }
                        .frame(height: 200)
                    }
                } header: {
                    Text("Max weight per week (kg)")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            points = (try? env.workouts.weeklyStatsForExercise(exerciseId: exerciseId, limitWeeks: 17)) ?? []
            if let info = try? env.exercises.exerciseHowTo(exerciseId: exerciseId) {
                title = info.displayName
            }
        }
    }
}
