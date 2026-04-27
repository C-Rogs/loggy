import Foundation

public struct ExerciseSummary: Identifiable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var exerciseMode: ExerciseMode
    public var isCustom: Bool
}

public struct WorkoutListItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var status: WorkoutSessionStatus
    public var totalVolumeKg: Double
    public var totalSetCount: Int
}

public struct ActiveWorkoutSummary: Hashable, Sendable {
    public var sessionId: String
    public var title: String?
    public var startedAt: Date
    public var recoveryState: RecoveryState
    public var lastOpenedAt: Date
}

public struct SessionExerciseCard: Identifiable, Hashable, Sendable {
    public var id: String
    public var exerciseId: String
    public var displayName: String
    public var exerciseMode: ExerciseMode
    public var notes: String?
    public var targetRestSeconds: Int?
    public var sets: [SetRowModel]
}

public struct SetRowModel: Identifiable, Hashable, Sendable {
    public var id: String
    public var setIndex: Int
    public var setType: SetType
    public var status: SetStatus
    public var weightKg: Double?
    public var reps: Int?
    public var distanceKm: Double?
    public var durationSeconds: Int?
    public var rpe: Double?
    public var completedAt: Date?
    public var previousDisplay: String
}

public struct WorkoutTemplateSummary: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var notes: String?
}

public struct ExerciseHowToInfo: Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var instructionText: String?
    public var gifURL: String?
}

public struct WeeklyVolumePoint: Identifiable, Hashable, Sendable {
    public var weekKey: String
    public var totalKg: Double

    public var id: String { weekKey }
}

public struct ExerciseWeeklyStatPoint: Identifiable, Hashable, Sendable {
    public var weekKey: String
    public var volumeKg: Double
    public var maxWeightKg: Double?

    public var id: String { weekKey }
}
