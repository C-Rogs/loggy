import SwiftUI

/// GitHub-style 26-week (≈6 months) contribution grid: 7 rows by ~26 columns. Cell tint blends a base session-count intensity with average RPE saturation.
struct WorkoutContributionHeatmapView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    @State private var rowsByDay: [String: DailyContributionRow] = [:]
    @State private var selectedDayKey: String?

    private let weeks = 26

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Last \(weeks) weeks")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                grid
                    .padding(.horizontal, 16)

                legend
                    .padding(.horizontal, 16)

                if let key = selectedDayKey, let row = rowsByDay[key] {
                    dayDetail(for: row)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 14)
        }
        .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        .navigationTitle("Workout streak")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .refreshable { reload() }
    }

    @ViewBuilder
    private var grid: some View {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: startOfToday) // 1=Sun
        let daysFromMonday = (weekday + 5) % 7
        let endOfWeek = cal.date(byAdding: .day, value: 6 - daysFromMonday, to: startOfToday) ?? startOfToday
        let firstCellDate = cal.date(byAdding: .day, value: -(weeks * 7 - 1), to: endOfWeek) ?? startOfToday

        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(0 ..< weeks, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0 ..< 7, id: \.self) { day in
                            let date = cal.date(byAdding: .day, value: week * 7 + day, to: firstCellDate) ?? firstCellDate
                            let key = Self.dayKey(for: date)
                            HeatmapCell(
                                date: date,
                                row: rowsByDay[key],
                                isFuture: date > Date(),
                                isSelected: key == selectedDayKey
                            )
                            .onTapGesture {
                                LoggyFeedback.listSelectionTap()
                                selectedDayKey = (selectedDayKey == key) ? nil : key
                            }
                        }
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            ForEach(0 ..< 5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(HeatmapCell.tint(forIntensity: Double(i) / 4.0, rpe: nil))
                    .frame(width: 12, height: 12)
            }
            Text("More")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func dayDetail(for row: DailyContributionRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.formatDayKeyForHumans(row.dayKey))
                .font(.subheadline.weight(.semibold))
            Text("\(row.sessionCount) workout\(row.sessionCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let rpe = row.avgRpe {
                Text(String(format: "Avg RPE %.1f", rpe))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func reload() {
        let limit = weeks * 7 + 7
        let rows = (try? env.workouts.dailyContributionRows(limitDays: limit)) ?? []
        rowsByDay = Dictionary(uniqueKeysWithValues: rows.map { ($0.dayKey, $0) })
    }

    static func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func formatDayKeyForHumans(_ key: String) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale.current
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: key) else { return key }
        f.dateStyle = .medium
        f.dateFormat = nil
        return f.string(from: date)
    }
}

private struct HeatmapCell: View {
    let date: Date
    let row: DailyContributionRow?
    let isFuture: Bool
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill)
            .frame(width: 12, height: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(isSelected ? Color.blue : .secondary.opacity(0.15), lineWidth: isSelected ? 1.5 : 0.5)
            )
            .opacity(isFuture ? 0.3 : 1)
    }

    private var fill: Color {
        if isFuture { return Color.gray.opacity(0.06) }
        guard let row, row.sessionCount > 0 else {
            return Color.gray.opacity(0.10)
        }
        let intensity = min(1.0, Double(row.sessionCount) / 2.0)
        return Self.tint(forIntensity: intensity, rpe: row.avgRpe)
    }

    /// 0…1 intensity by session count, modulated by RPE so a high-effort single workout reads brighter than a junk-volume day.
    static func tint(forIntensity intensity: Double, rpe: Double?) -> Color {
        let rpeBoost = rpe.map { max(0, min(1, ($0 - 5) / 5)) } ?? 0
        let combined = min(1, 0.25 + 0.55 * intensity + 0.20 * rpeBoost)
        return Color.green.opacity(combined)
    }
}
