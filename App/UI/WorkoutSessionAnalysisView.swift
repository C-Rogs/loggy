import Charts
import GRDB
import SwiftUI

struct WorkoutSessionAnalysisView: View {
    @Binding var homePath: [HomeRoute]
    let sessionId: String

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var appleHealth: AppleHealthWorkoutService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    @State private var title: String = ""
    @State private var startedAt: Date?
    @State private var endedAt: Date?
    @State private var durationSeconds: Int = 0
    @State private var volumeKg: Double = 0
    @State private var setCount: Int = 0
    @State private var repCount: Int = 0
    @State private var sessionStatus: WorkoutSessionStatus = .completed

    @State private var heartPoints: [HeartRateSamplePoint] = []
    @State private var heartEmptyReason: String?

    @State private var templateMessage: String?
    @State private var showTemplateAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerBlock

                if !heartPoints.isEmpty {
                    heartChartSection
                } else if let heartEmptyReason {
                    Text(heartEmptyReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollContentBackground(.hidden)
        .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Save as template") { saveAsTemplate() }
                    Button("Edit workout") {
                        homePath.append(.editor(sessionId))
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .toolbarBackground(
            LoggyTheme.navigationBarBackground(oledPreference: loggyOLEDDark, colorScheme: colorScheme),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await load() }
        .alert("Template", isPresented: $showTemplateAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(templateMessage ?? "")
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Workout" : title)
                .font(.title2.weight(.semibold))

            if let startedAt {
                Text(dateRangeLine(start: startedAt, end: endedAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 12
            ) {
                statCell(label: "Duration", value: formatDuration(durationSeconds))
                statCell(label: "Volume", value: "\(Int(volumeKg)) kg")
                statCell(label: "Sets", value: "\(setCount)")
                statCell(label: "Reps", value: "\(repCount)")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.materialCornerRadius, style: .continuous)
                    .fill(LoggyTheme.structuralBarFill(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
            )

            if sessionStatus == .discarded {
                Text("This session was discarded; totals may be incomplete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var heartChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart rate")
                .font(.headline)
            Chart(heartPoints) { pt in
                LineMark(
                    x: .value("Time", pt.date),
                    y: .value("BPM", pt.bpm)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.red)
            }
            .chartXAxis(.automatic)
            .chartYAxis(.automatic)
            .frame(height: 180)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.materialCornerRadius, style: .continuous)
                .fill(LoggyTheme.elevatedGroupedCard(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        )
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dateRangeLine(start: Date, end: Date?) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        if let end {
            return "\(df.string(from: start)) – \(df.string(from: end))"
        }
        return df.string(from: start)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private func load() async {
        do {
            let meta = try env.workouts.loadSessionForEdit(sessionId: sessionId)
            sessionStatus = meta.status
            title = meta.title ?? ""

            let row = try await env.database.pool.read { db in
                try Row.fetchOne(
                    db,
                    sql: """
                        SELECT started_at, ended_at, total_duration_seconds_cache,
                               total_volume_kg_cache, total_set_count_cache, total_rep_count_cache
                        FROM workout_session
                        WHERE id = ? AND deleted_at IS NULL
                        """,
                    arguments: [sessionId]
                )
            }
            if let row {
                let startedStr: String? = row["started_at"]
                let endedStr: String? = row["ended_at"]
                startedAt = startedStr.flatMap(ISO8601UTC.date(from:))
                if let endedStr, !endedStr.isEmpty {
                    endedAt = ISO8601UTC.date(from: endedStr)
                } else {
                    endedAt = nil
                }
                if let startedAt, let end = endedAt {
                    durationSeconds = max(0, Int(end.timeIntervalSince(startedAt)))
                } else if let cache: Int = row["total_duration_seconds_cache"] {
                    durationSeconds = max(0, cache)
                } else if let cache: Int64 = row["total_duration_seconds_cache"] {
                    durationSeconds = max(0, Int(cache))
                } else {
                    durationSeconds = 0
                }
                volumeKg = row["total_volume_kg_cache"]
                setCount = {
                    if let v: Int = row["total_set_count_cache"] { return v }
                    if let v: Int64 = row["total_set_count_cache"] { return Int(v) }
                    return 0
                }()
                if let n = row["total_rep_count_cache"] as? Int64 {
                    repCount = Int(n)
                } else if let n = row["total_rep_count_cache"] as? Int {
                    repCount = n
                } else {
                    repCount = 0
                }
            }
        } catch {
            title = "Workout"
        }

        let samples = await appleHealth.heartRateSamplesBpm(sessionId: sessionId)
        heartPoints = samples
        if samples.isEmpty {
            if !appleHealth.isHealthDataAvailable {
                heartEmptyReason = "Health data is not available on this device."
            } else if !appleHealth.syncWorkoutsToHealthEnabled {
                heartEmptyReason = "Turn on “Save workouts to Health” and allow heart rate read access to chart BPM for this session."
            } else {
                heartEmptyReason = "No heart rate samples in Health for this session window (try logging with Apple Watch)."
            }
        } else {
            heartEmptyReason = nil
        }
    }

    private func saveAsTemplate() {
        do {
            _ = try env.templates.createTemplate(fromSessionId: sessionId)
            templateMessage = "Template saved. Open Templates from the home screen to use it."
            showTemplateAlert = true
        } catch TemplateRepositoryError.sessionNotCompleted {
            templateMessage = "Only completed workouts can be saved as a template."
            showTemplateAlert = true
        } catch {
            templateMessage = String(describing: error)
            showTemplateAlert = true
        }
    }
}
