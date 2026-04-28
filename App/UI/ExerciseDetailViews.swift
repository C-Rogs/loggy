import Charts
import SwiftUI

private enum ExerciseInfoTab: String, CaseIterable, Identifiable {
    case summary = "Summary"
    case history = "History"
    case howTo = "How to"

    var id: String { rawValue }
}

/// Full exercise detail: summary (GIF + muscles), history charts, how-to text.
struct ExerciseInfoView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark
    @Environment(\.dismiss) private var dismiss

    let exerciseId: String
    /// When `true`, show a Done button (e.g. sheet from active workout).
    var showDismissInToolbar: Bool = false

    @State private var info: ExerciseHowToInfo?
    @State private var tab: ExerciseInfoTab = .summary

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(ExerciseInfoTab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Group {
                switch tab {
                case .summary:
                    exerciseSummaryScroll
                case .history:
                    ExerciseHistoryChartsView(exerciseId: exerciseId)
                case .howTo:
                    exerciseHowToScroll
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if showDismissInToolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            info = try? env.exercises.exerciseHowTo(exerciseId: exerciseId)
        }
    }

    private var exerciseSummaryScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                exerciseGifBlock(maxHeight: 280)
                if let p = info?.primaryMuscleGroup, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Primary: \(MuscleDisplayName.forStoredSlug(p))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let secs = info?.secondaryMuscleGroups, !secs.isEmpty {
                    let labels = secs.map { MuscleDisplayName.forStoredSlug($0) }.joined(separator: ", ")
                    Text("Secondary: \(labels)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Button {
                    tab = .howTo
                } label: {
                    Label("How to log this exercise", systemImage: "lightbulb")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private var exerciseHowToScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                exerciseGifBlock(maxHeight: 260)
                if let t = info?.instructionText, !t.isEmpty {
                    Text(t)
                        .font(.body)
                } else {
                    Text("No written instructions yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    @ViewBuilder
    private func exerciseGifBlock(maxHeight: CGFloat) -> some View {
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
                        .frame(maxHeight: maxHeight)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.materialCornerRadius, style: .continuous))
                case .failure:
                    ContentUnavailableView("Could not load image", systemImage: "photo")
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}

struct ExerciseHistoryChartsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark
    let exerciseId: String

    @State private var buckets: [ExerciseHistoryBucket] = []
    @State private var metric: ExerciseHistoryMetric = .bestSetVolume
    @State private var timeRange: ExerciseHistoryTimeRange = .year

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ExerciseHistoryMetric.allCases) { m in
                            Button {
                                metric = m
                            } label: {
                                Text(m.title)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(metric == m ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Picker("Range", selection: $timeRange) {
                    ForEach(ExerciseHistoryTimeRange.allCases) { r in
                        Text(r.title).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: timeRange) { _, _ in reload() }
            }

            if buckets.isEmpty {
                Section {
                    Text("Complete workouts with this exercise to see trends.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    if let headline = headlineText {
                        Text(headline)
                            .font(.title3.weight(.bold))
                    }
                    Chart(buckets) { b in
                        LineMark(
                            x: .value("Period", b.periodKey),
                            y: .value(metric.title, yValue(b))
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.blue.gradient)
                    }
                    .frame(height: 220)
                } header: {
                    Text(chartFootnote)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        .task {
            reload()
        }
    }

    private var chartFootnote: String {
        switch metric {
        case .heaviestWeight: return "Heaviest completed set (kg) per period."
        case .estimatedOneRM: return "Estimated 1RM (Brzycki) from completed sets."
        case .bestSetVolume: return "Best single-set volume (kg × reps) per period."
        case .sessionVolume: return "Strongest session volume (sum of sets) per period."
        case .totalReps: return "Total reps logged per period."
        }
    }

    private func yValue(_ b: ExerciseHistoryBucket) -> Double {
        switch metric {
        case .heaviestWeight: return b.heaviestWeightKg ?? 0
        case .estimatedOneRM: return b.estimatedOneRMKg ?? 0
        case .bestSetVolume: return b.bestSetVolumeKg
        case .sessionVolume: return b.bestSessionVolumeKg
        case .totalReps: return Double(b.totalReps)
        }
    }

    private var headlineText: String? {
        guard let best = buckets.max(by: { yValue($0) < yValue($1) }) else { return nil }
        let v = yValue(best)
        guard v > 0 else { return nil }
        let suffix: String = {
            switch metric {
            case .totalReps: return "\(Int(v)) reps"
            default: return String(format: "%.2f kg", v)
            }
        }()
        return "\(suffix) · \(best.sortDate)"
    }

    private func reload() {
        buckets = (try? env.workouts.exerciseHistoryBuckets(exerciseId: exerciseId, range: timeRange)) ?? []
    }
}
