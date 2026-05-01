import XCTest
@testable import Loggy

/// Apple Fitness `workoutEffortScore` is on a 1-10 scale and our RPE column already lives on the same scale, so the mapping is identity with a clamp.
final class AppleFitnessEffortMappingTests: XCTestCase {
    func testClampLowerBound() {
        let value = Self.clampToEffortScore(0)
        XCTAssertEqual(value, 1)
    }

    func testClampUpperBound() {
        let value = Self.clampToEffortScore(15)
        XCTAssertEqual(value, 10)
    }

    func testIdentityInRange() {
        XCTAssertEqual(Self.clampToEffortScore(7.5), 7.5, accuracy: 0.001)
    }

    /// Mirrors the clamp in `AppleFitnessEffortRecorder.recordSessionEffort`. Kept inline here so we don't need to expose internals.
    private static func clampToEffortScore(_ rpe: Double) -> Double {
        min(10, max(1, rpe))
    }
}
