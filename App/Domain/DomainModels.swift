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
    public var primaryMuscleGroup: String?
    public var secondaryMuscleGroups: [String]

    public init(
        id: String,
        displayName: String,
        instructionText: String?,
        gifURL: String?,
        primaryMuscleGroup: String? = nil,
        secondaryMuscleGroups: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.instructionText = instructionText
        self.gifURL = gifURL
        self.primaryMuscleGroup = primaryMuscleGroup
        self.secondaryMuscleGroups = secondaryMuscleGroups
    }
}

// MARK: - Exercise history (charts)

public enum ExerciseHistoryTimeRange: String, CaseIterable, Identifiable, Sendable {
    case month
    case year
    case allTime

    public var id: String { rawValue }

    /// SQLite `date('now', ?)` second argument, e.g. `-365 days`; `nil` = all time.
    public var dateFilterArgument: String? {
        switch self {
        case .month: return "-120 days"
        case .year: return "-800 days"
        case .allTime: return nil
        }
    }

    public var title: String {
        switch self {
        case .month: return "Month"
        case .year: return "Year"
        case .allTime: return "All"
        }
    }
}

public enum ExerciseHistoryMetric: String, CaseIterable, Identifiable, Sendable {
    case heaviestWeight
    case estimatedOneRM
    case bestSetVolume
    case sessionVolume
    case totalReps

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .heaviestWeight: return "Heaviest weight"
        case .estimatedOneRM: return "One Rep Max"
        case .bestSetVolume: return "Best set volume"
        case .sessionVolume: return "Session volume"
        case .totalReps: return "Total reps"
        }
    }
}

public struct ExerciseHistoryBucket: Identifiable, Hashable, Sendable {
    public var periodKey: String
    public var sortDate: String
    public var heaviestWeightKg: Double?
    public var estimatedOneRMKg: Double?
    public var bestSetVolumeKg: Double
    public var bestSessionVolumeKg: Double
    public var totalReps: Int

    public var id: String { periodKey }
}

public struct MuscleGroupSetCount: Identifiable, Hashable, Sendable {
    public var muscleSlug: String
    public var displayLabel: String
    public var completedSetCount: Int

    public var id: String { muscleSlug }
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
