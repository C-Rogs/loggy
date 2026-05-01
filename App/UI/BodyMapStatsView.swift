import SwiftUI

/// Front + back body silhouette tinted by 7-day muscle volume share — Hevy-style at-a-glance view of where the user has trained recently.
///
/// Implementation note: rather than ship an SVG-derived asset graph, this draws coarse-grained rounded rectangles per muscle bucket on top of a lightweight stick-figure outline. That's intentional: it stays compatible with `ExerciseMuscleBucket` (chest / back / shoulders / legs / arms / core) without introducing a new taxonomy, and renders cleanly at any size.
struct BodyMapStatsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.loggyOLEDDarkUserPreference) private var loggyOLEDDark

    @State private var counts: [String: Int] = [:]
    @State private var totalSets: Int = 0
    @State private var showDetailedList = false

    private let windowDays = 7

    private static let buckets: [(slug: String, label: String)] = [
        ("chest", "Chest"),
        ("back", "Back"),
        ("shoulders", "Shoulders"),
        ("arms", "Arms"),
        ("legs", "Legs"),
        ("core", "Core"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Last 7 days")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                HStack(alignment: .top, spacing: 12) {
                    BodySilhouette(side: .front, share: shareBySlug)
                    BodySilhouette(side: .back, share: shareBySlug)
                }
                .padding(.horizontal, 16)

                muscleLegend
                    .padding(.horizontal, 16)

                Toggle("Detailed list", isOn: $showDetailedList)
                    .padding(.horizontal, 16)
                if showDetailedList {
                    MuscleDistributionBodyView()
                        .frame(minHeight: 360)
                }
            }
            .padding(.vertical, 14)
        }
        .background(LoggyTheme.groupedCanvas(oledPreference: loggyOLEDDark, colorScheme: colorScheme))
        .navigationTitle("Body map")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .refreshable { reload() }
    }

    private var shareBySlug: [String: Double] {
        guard totalSets > 0 else { return [:] }
        var out: [String: Double] = [:]
        for (k, v) in counts {
            out[k] = Double(v) / Double(totalSets)
        }
        return out
    }

    @ViewBuilder
    private var muscleLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Self.buckets, id: \.slug) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(BodySilhouette.tint(forShare: shareBySlug[item.slug] ?? 0))
                        .frame(width: 10, height: 10)
                    Text(item.label)
                        .font(.caption)
                    Spacer(minLength: 0)
                    Text("\(counts[item.slug] ?? 0) sets")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func reload() {
        let rows = (try? env.workouts.completedSetCountsByPrimaryMuscle(sinceDaysAgo: windowDays)) ?? []
        var dict: [String: Int] = [:]
        var total = 0
        for r in rows {
            let slug = Self.coarseSlug(forMuscleSlug: r.muscleSlug.lowercased())
            dict[slug, default: 0] += r.completedSetCount
            total += r.completedSetCount
        }
        counts = dict
        totalSets = total
    }

    private static func coarseSlug(forMuscleSlug slug: String) -> String {
        switch slug {
        case "chest": return "chest"
        case "upper back", "lats", "lower back", "traps": return "back"
        case "shoulders": return "shoulders"
        case "biceps", "triceps", "forearms": return "arms"
        case "quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors", "hip flexors": return "legs"
        case "abs": return "core"
        default: return "other"
        }
    }
}

/// Single-side silhouette. We render six rectangular muscle regions on top of a head + torso + limbs outline. Not anatomically perfect, but readable and tappable on small devices.
private struct BodySilhouette: View {
    enum Side { case front, back }

    let side: Side
    let share: [String: Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = w * 1.7
            ZStack {
                outline(width: w, height: h)
                regions(width: w, height: h)
            }
            .frame(width: w, height: h)
            .frame(maxWidth: .infinity)
        }
        .aspectRatio(1.0 / 1.7, contentMode: .fit)
        .overlay(alignment: .bottom) {
            Text(side == .front ? "Front" : "Back")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
        }
    }

    @ViewBuilder
    private func outline(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                .frame(width: w * 0.28, height: w * 0.28)
                .position(x: w / 2, y: h * 0.09)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                .frame(width: w * 0.55, height: h * 0.32)
                .position(x: w / 2, y: h * 0.32)
        }
    }

    @ViewBuilder
    private func regions(width w: CGFloat, height h: CGFloat) -> some View {
        let chest = side == .front
        let absVisible = side == .front
        let backVisible = side == .back
        let glutesVisible = side == .back

        // Shoulders (both sides)
        Capsule()
            .fill(Self.tint(forShare: share["shoulders"] ?? 0))
            .frame(width: w * 0.55, height: h * 0.05)
            .position(x: w / 2, y: h * 0.20)

        if chest {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Self.tint(forShare: share["chest"] ?? 0))
                .frame(width: w * 0.42, height: h * 0.10)
                .position(x: w / 2, y: h * 0.27)
        }
        if backVisible {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Self.tint(forShare: share["back"] ?? 0))
                .frame(width: w * 0.42, height: h * 0.18)
                .position(x: w / 2, y: h * 0.30)
        }
        if absVisible {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Self.tint(forShare: share["core"] ?? 0))
                .frame(width: w * 0.32, height: h * 0.10)
                .position(x: w / 2, y: h * 0.42)
        }
        if glutesVisible {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Self.tint(forShare: share["legs"] ?? 0))
                .frame(width: w * 0.42, height: h * 0.08)
                .position(x: w / 2, y: h * 0.50)
        }

        // Arms
        Capsule()
            .fill(Self.tint(forShare: share["arms"] ?? 0))
            .frame(width: w * 0.10, height: h * 0.22)
            .position(x: w * 0.18, y: h * 0.36)
        Capsule()
            .fill(Self.tint(forShare: share["arms"] ?? 0))
            .frame(width: w * 0.10, height: h * 0.22)
            .position(x: w * 0.82, y: h * 0.36)

        // Legs
        Capsule()
            .fill(Self.tint(forShare: share["legs"] ?? 0))
            .frame(width: w * 0.14, height: h * 0.30)
            .position(x: w * 0.40, y: h * 0.72)
        Capsule()
            .fill(Self.tint(forShare: share["legs"] ?? 0))
            .frame(width: w * 0.14, height: h * 0.30)
            .position(x: w * 0.60, y: h * 0.72)
    }

    /// Map 0…1 share into a tint between near-clear (`Color.gray.opacity(0.10)`) and saturated red (`Color.red.opacity(0.85)`).
    static func tint(forShare share: Double) -> Color {
        let s = max(0, min(1, share * 3))
        return Color.red.opacity(0.10 + 0.7 * s)
    }
}
