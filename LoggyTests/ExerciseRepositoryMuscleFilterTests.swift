import GRDB
import XCTest
@testable import Loggy

final class ExerciseRepositoryMuscleFilterTests: XCTestCase {
    func testSearchFiltersByPrimaryMuscleSlug() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("loggy-ex-filter-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: url.path, configuration: config)
        try AppMigrator().migrate(pool)

        let chestId = UUID().uuidString
        let legId = UUID().uuidString
        let now = ISO8601UTC.string(from: Date())
        let uniqueChestSlug = "loggy_test_chest_\(chestId.prefix(8))"

        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO exercise (id, canonical_name, display_name, exercise_mode, equipment_type,
                        primary_muscle_group, secondary_muscle_groups_json, is_custom, sort_name, created_at, updated_at)
                    VALUES (?, 'fly', 'Fly', 'weight_reps', NULL, ?, '[]', 0, 'fly', ?, ?)
                    """,
                arguments: [chestId, uniqueChestSlug, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO exercise (id, canonical_name, display_name, exercise_mode, equipment_type,
                        primary_muscle_group, secondary_muscle_groups_json, is_custom, sort_name, created_at, updated_at)
                    VALUES (?, 'squat', 'Squat', 'weight_reps', NULL, 'quadriceps', '[]', 0, 'squat', ?, ?)
                    """,
                arguments: [legId, now, now]
            )
        }

        let repo = ExerciseRepository(pool: pool)
        let chestOnly = try repo.searchExercises(query: "", primaryMuscleSlug: uniqueChestSlug, exerciseMode: nil)
        XCTAssertEqual(chestOnly.count, 1)
        XCTAssertEqual(chestOnly[0].id, chestId)

        let legsOnly = try repo.searchExercises(query: "", primaryMuscleSlug: "quadriceps", exerciseMode: nil)
        XCTAssertTrue(legsOnly.map(\.id).contains(legId))
    }
}
