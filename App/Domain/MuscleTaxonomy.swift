import Foundation

/// Primary muscle slugs aligned with `Docs/EXERCISE_MUSCLE_TAXONOMY.md` for filters and charts.
public enum MuscleTaxonomy: Sendable {
    /// Slugs stored on `exercise.primary_muscle_group` for catalogue filtering (order is UI order).
    public static let primaryFilterSlugs: [String] = [
        "chest",
        "upper back",
        "lats",
        "lower back",
        "traps",
        "shoulders",
        "biceps",
        "triceps",
        "forearms",
        "quadriceps",
        "hamstrings",
        "glutes",
        "calves",
        "abs",
        "hip flexors",
        "adductors",
        "abductors",
        "cardio",
        "neck"
    ]

    public static func filterChipLabel(forSlug slug: String) -> String {
        MuscleDisplayName.forStoredSlug(slug)
    }
}
