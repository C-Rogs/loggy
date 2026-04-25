import Foundation
import GRDB

public final class CoachRepository: CoachRepositoryProtocol {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func insertRecommendation(
        scope: CoachScope,
        workoutSessionId: String?,
        workoutSessionExerciseId: String?,
        setEntryId: String?,
        type: String,
        payloadJSON: String
    ) throws -> String {
        let id = UUID().uuidString
        let now = ISO8601UTC.string(from: Date())
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO coach_recommendation (
                        id, scope, workout_session_id, workout_session_exercise_id, set_entry_id,
                        recommendation_type, payload_json, confidence, model_version, generated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, 'rules_v1', ?)
                """,
                arguments: [
                    id, scope.rawValue, workoutSessionId, workoutSessionExerciseId, setEntryId,
                    type, payloadJSON, now
                ]
            )
        }
        return id
    }
}
