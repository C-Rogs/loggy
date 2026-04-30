import Foundation

public struct ExerciseSummary: Identifiable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var exerciseMode: ExerciseMode
    public var isCustom: Bool
    /// Primary muscle slug from `exercise.primary_muscle_group`, when loaded.
    public var primaryMuscleGroup: String?

    public init(
        id: String,
        displayName: String,
        exerciseMode: ExerciseMode,
        isCustom: Bool,
        primaryMuscleGroup: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.exerciseMode = exerciseMode
        self.isCustom = isCustom
        self.primaryMuscleGroup = primaryMuscleGroup
    }
}

/// Completed-set frequency for an exercise (attributed via `logged_exercise_id` when set).
public struct ExerciseSetFrequencyRow: Identifiable, Hashable, Sendable {
    public var exerciseId: String
    public var displayName: String
    public var completedSetCount: Int

    public var id: String { exerciseId }
}

/// Coarse muscle bucket totals for comparing two time windows (e.g. last 30 days vs prior 30 days).
public struct MuscleCoarseDistributionRow: Identifiable, Hashable, Sendable {
    public var bucketRaw: String
    public var title: String
    public var currentSetCount: Int
    public var previousSetCount: Int

    public var id: String { bucketRaw }
}

/// One calendar week of completed sets by primary muscle slug (for weekly breakdown UI).
public struct WeeklyMuscleSetRow: Identifiable, Hashable, Sendable {
    public var weekKey: String
    public var sortDateLabel: String
    public var muscles: [MuscleGroupSetCount]

    public var id: String { weekKey }
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

/// One line in a workout template: exercise identity plus optional targets for seeding planned sets.
public struct TemplateExerciseRow: Identifiable, Hashable, Sendable {
    /// `workout_template_exercise.id`
    public var id: String
    public var exercise: ExerciseSummary
    public var targetSetCount: Int?
    public var targetRepMin: Int?
    public var targetRepMax: Int?
    public var targetWeightKg: Double?
    public var targetDurationSeconds: Int?
    public var targetDistanceKm: Double?
    public var defaultSetType: SetType
    public var defaultRestSeconds: Int?
    public var notes: String?

    public init(
        id: String,
        exercise: ExerciseSummary,
        targetSetCount: Int?,
        targetRepMin: Int?,
        targetRepMax: Int?,
        targetWeightKg: Double?,
        targetDurationSeconds: Int?,
        targetDistanceKm: Double?,
        defaultSetType: SetType,
        defaultRestSeconds: Int?,
        notes: String?
    ) {
        self.id = id
        self.exercise = exercise
        self.targetSetCount = targetSetCount
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.targetWeightKg = targetWeightKg
        self.targetDurationSeconds = targetDurationSeconds
        self.targetDistanceKm = targetDistanceKm
        self.defaultSetType = defaultSetType
        self.defaultRestSeconds = defaultRestSeconds
        self.notes = notes
    }
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

/// String formatting for set-entry numeric fields (avoids Swift `String(Double)` adding `.0` for whole numbers).
public enum LoggyMetricDisplay {
    public static func kgForTextField(_ kg: Double?) -> String {
        guard let kg else { return "" }
        let r = abs(kg.truncatingRemainder(dividingBy: 1))
        if r < 1e-9 || abs(r - 1) < 1e-9 {
            return String(Int(round(kg)))
        }
        var s = String(format: "%.2f", kg)
        while s.last == "0" { s.removeLast() }
        while s.last == "." { s.removeLast() }
        return s
    }

    public static func kmForTextField(_ km: Double?) -> String {
        guard let km else { return "" }
        let r = abs(km.truncatingRemainder(dividingBy: 1))
        if r < 1e-9 || abs(r - 1) < 1e-9 {
            return String(Int(round(km)))
        }
        var s = String(format: "%.3f", km)
        while s.last == "0" { s.removeLast() }
        while s.last == "." { s.removeLast() }
        return s
    }
}
