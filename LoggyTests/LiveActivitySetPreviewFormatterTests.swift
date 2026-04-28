import XCTest
@testable import Loggy

final class LiveActivitySetPreviewFormatterTests: XCTestCase {
    func testSameExerciseNextSetUsesSetLabel() {
        let s1 = set(id: "s1", index: 0, type: .normal, weight: 60, reps: 8)
        let s2 = set(id: "s2", index: 1, type: .normal, weight: 62.5, reps: 6)
        let card = card(id: "c1", name: "Bench", mode: .weightReps, sets: [s1, s2])
        let line = LiveActivitySetPreviewFormatter.nextPlannedSetLine(
            exercises: [card],
            card: card,
            currentSetId: "s1"
        )
        XCTAssertEqual(line, "Set 2: 62.5 kg x 6")
    }

    func testNextExerciseUsesDisplayNamePrefix() {
        let s1 = set(id: "s1", index: 0, type: .normal, weight: 100, reps: 5)
        let s2 = set(id: "s2", index: 0, type: .normal, weight: 40, reps: 12)
        let c1 = card(id: "c1", name: "Squat", mode: .weightReps, sets: [s1])
        let c2 = card(id: "c2", name: "Dumbbell Row", mode: .weightReps, sets: [s2])
        let line = LiveActivitySetPreviewFormatter.nextPlannedSetLine(
            exercises: [c1, c2],
            card: c1,
            currentSetId: "s1"
        )
        XCTAssertEqual(line, "Dumbbell Row: 40.0 kg x 12")
    }

    func testWarmupLabel() {
        let s1 = set(id: "s1", index: 0, type: .warmup, weight: 20, reps: 10)
        let s2 = set(id: "s2", index: 1, type: .normal, weight: 100, reps: 5)
        let card = card(id: "c1", name: "Press", mode: .weightReps, sets: [s1, s2])
        let line = LiveActivitySetPreviewFormatter.nextPlannedSetLine(
            exercises: [card],
            card: card,
            currentSetId: "s1"
        )
        XCTAssertEqual(line, "Set 2: 100.0 kg x 5")
    }

    private func set(
        id: String,
        index: Int,
        type: SetType,
        weight: Double?,
        reps: Int?
    ) -> SetRowModel {
        SetRowModel(
            id: id,
            setIndex: index,
            setType: type,
            status: .planned,
            weightKg: weight,
            reps: reps,
            distanceKm: nil,
            durationSeconds: nil,
            rpe: nil,
            completedAt: nil,
            previousDisplay: "—"
        )
    }

    private func card(id: String, name: String, mode: ExerciseMode, sets: [SetRowModel]) -> SessionExerciseCard {
        SessionExerciseCard(
            id: id,
            exerciseId: "ex-\(id)",
            displayName: name,
            exerciseMode: mode,
            notes: nil,
            targetRestSeconds: 90,
            sets: sets
        )
    }
}
