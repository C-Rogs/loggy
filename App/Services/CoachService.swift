import Foundation

/// Rules-first intra-session coach: records advisory rows only; never mutates canonical sets.
final class CoachService: @unchecked Sendable {
    private let coach: CoachRepositoryProtocol

    init(coach: CoachRepositoryProtocol) {
        self.coach = coach
    }

    func recordIntraSessionRepDropoff(
        workoutSessionId: String,
        workoutSessionExerciseId: String,
        setEntryId: String,
        previousReps: Int?,
        currentReps: Int?
    ) {
        guard let previousReps, let currentReps, previousReps > 0 else { return }
        let drop = Double(previousReps - currentReps) / Double(previousReps)
        guard drop >= 0.2 else { return }

        let payload = """
        {"reason":"rep_dropoff","previous_reps":\(previousReps),"current_reps":\(currentReps),"drop_ratio":\(drop)}
        """
        try? coach.insertRecommendation(
            scope: .intraSession,
            workoutSessionId: workoutSessionId,
            workoutSessionExerciseId: workoutSessionExerciseId,
            setEntryId: setEntryId,
            type: "rep_dropoff",
            payloadJSON: payload
        )
    }
}
