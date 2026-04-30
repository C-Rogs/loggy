import GRDB
import XCTest
@testable import Loggy

/// Active-session guard (one workout at a time) and template → planned set seeding.
final class WorkoutSessionActiveSessionTemplateTests: XCTestCase {
    /// Closes the pool before deleting the temp file to avoid sqlite “vnode unlinked while in use” warnings.
    private func withMigratedPool(_ body: (DatabasePool) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("loggy-ws-template-\(UUID().uuidString).sqlite")
        var config = Configuration()
        config.foreignKeysEnabled = true
        var pool: DatabasePool? = try DatabasePool(path: url.path, configuration: config)
        try AppMigrator().migrate(pool!)
        do {
            try body(pool!)
        }
        pool = nil
        try? FileManager.default.removeItem(at: url)
    }

    func testSecondEmptyActiveSessionThrows() throws {
        try withMigratedPool { pool in
            let workouts = WorkoutSessionRepository(pool: pool)
            _ = try workouts.createEmptyActiveSession(title: "A")
            XCTAssertThrowsError(try workouts.createEmptyActiveSession(title: "B")) { error in
                guard case RepositoryError.activeSessionAlreadyExists = error else {
                    XCTFail("Expected activeSessionAlreadyExists, got \(error)")
                    return
                }
            }
        }
    }

    func testStartFromTemplateWhenActiveThrows() throws {
        try withMigratedPool { pool in
            let workouts = WorkoutSessionRepository(pool: pool)
            let templates = TemplateRepository(pool: pool)
            let now = ISO8601UTC.string(from: Date())
            let exId = UUID().uuidString
            try pool.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO exercise (id, canonical_name, display_name, exercise_mode, equipment_type,
                            primary_muscle_group, secondary_muscle_groups_json, is_custom, sort_name, created_at, updated_at)
                        VALUES (?, 't1', 'T1', 'weight_reps', NULL, 'chest', '[]', 0, 't1', ?, ?)
                        """,
                    arguments: [exId, now, now]
                )
            }
            let tplId = try templates.createTemplate(name: "T")
            try templates.addExerciseToTemplate(templateId: tplId, exerciseId: exId)
            _ = try workouts.createEmptyActiveSession(title: nil)
            XCTAssertThrowsError(try workouts.startSessionFromTemplate(templateId: tplId, title: nil)) { error in
                guard case RepositoryError.activeSessionAlreadyExists = error else {
                    XCTFail("Expected activeSessionAlreadyExists, got \(error)")
                    return
                }
            }
        }
    }

    func testStartFromTemplateSeedsPlannedSetsFromTargets() throws {
        try withMigratedPool { pool in
            let workouts = WorkoutSessionRepository(pool: pool)
            let templates = TemplateRepository(pool: pool)
            let now = ISO8601UTC.string(from: Date())
            let exId = UUID().uuidString
            try pool.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO exercise (id, canonical_name, display_name, exercise_mode, equipment_type,
                            primary_muscle_group, secondary_muscle_groups_json, is_custom, sort_name, created_at, updated_at)
                        VALUES (?, 'press', 'Press', 'weight_reps', NULL, 'chest', '[]', 0, 'press', ?, ?)
                        """,
                    arguments: [exId, now, now]
                )
            }
            let tplId = try templates.createTemplate(name: "Push")
            try templates.addExerciseToTemplate(templateId: tplId, exerciseId: exId)
            var rows = try templates.listTemplateExerciseRows(templateId: tplId)
            XCTAssertEqual(rows.count, 1)
            try templates.updateTemplateExerciseTargets(
                templateExerciseId: rows[0].id,
                targetSetCount: 2,
                targetRepMin: 8,
                targetRepMax: 10,
                targetWeightKg: 62.5,
                targetDurationSeconds: nil,
                targetDistanceKm: nil
            )
            rows = try templates.listTemplateExerciseRows(templateId: tplId)
            XCTAssertEqual(rows[0].targetSetCount, 2)

            let sessionId = try workouts.startSessionFromTemplate(templateId: tplId, title: nil)
            let cards = try workouts.sessionExercises(sessionId: sessionId)
            XCTAssertEqual(cards.count, 1)
            XCTAssertEqual(cards[0].sets.count, 2)
            for s in cards[0].sets {
                XCTAssertEqual(s.status, .planned)
                XCTAssertEqual(s.weightKg, 62.5)
                XCTAssertEqual(s.reps, 9)
            }
        }
    }
}
