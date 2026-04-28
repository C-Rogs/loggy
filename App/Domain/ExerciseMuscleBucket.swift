import Foundation

/// Coarse muscle / movement family used to suggest same-slot exercise swaps (e.g. bench → dumbbell bench).
enum ExerciseMuscleBucket: String, Sendable, CaseIterable {
    case chest
    case back
    case shoulders
    case legs
    case arms
    case core
    case cardio
    case unknown

    /// Buckets from persisted `primary_muscle_group` / taxonomy slugs, then substring heuristics, then exercise titles.
    static func bucket(
        primaryMuscle: String?,
        displayName: String,
        canonicalName: String
    ) -> ExerciseMuscleBucket {
        if let p = primaryMuscle?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            let key = p.lowercased()
            if let b = coarseBucketFromStoredSlug(key) { return b }
            if let b = bucketFromMuscleLabel(p) { return b }
        }
        return bucketFromExerciseTitle(displayName: displayName, canonicalName: canonicalName)
    }

    /// Maps taxonomy slugs (see `Docs/EXERCISE_MUSCLE_TAXONOMY.md`) to coarse buckets.
    static func coarseBucketFromStoredSlug(_ slug: String) -> ExerciseMuscleBucket? {
        switch slug {
        case "chest": return .chest
        case "upper back", "lats", "lower back", "traps": return .back
        case "shoulders": return .shoulders
        case "biceps", "triceps", "forearms": return .arms
        case "quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors", "hip flexors": return .legs
        case "abs": return .core
        case "cardio": return .cardio
        case "neck": return .unknown
        default: return nil
        }
    }

    private static func bucketFromMuscleLabel(_ raw: String) -> ExerciseMuscleBucket? {
        let s = raw.lowercased()
        if s.contains("chest") || s.contains("pectoral") { return .chest }
        if s.contains("lat") || s.contains("back") || s.contains("trap") || s.contains("rhomboid") { return .back }
        if s.contains("shoulder") || s.contains("delt") { return .shoulders }
        if s.contains("bicep") || s.contains("tricep") || s.contains("forearm") || s.contains("brachial") { return .arms }
        if s.contains("quad") || s.contains("hamstring") || s.contains("glute") || s.contains("calf")
            || s.contains("leg") || s.contains("hip") || s.contains("adductor") || s.contains("abductor")
        {
            return .legs
        }
        if s.contains("core") || s.contains("abdominal") || s.contains("oblique") { return .core }
        if s.contains("cardio") { return .cardio }
        return nil
    }

    /// Keyword rules ordered **longest first** so e.g. "romanian deadlift" beats "deadlift" → back vs legs tie-break.
    private static func bucketFromExerciseTitle(displayName: String, canonicalName: String) -> ExerciseMuscleBucket {
        let h = (displayName + " " + canonicalName).lowercased()

        let rules: [(String, ExerciseMuscleBucket)] = [
            ("bulgarian split squat", .legs),
            ("romanian deadlift", .legs),
            ("lat pulldown", .back),
            ("leg press", .legs),
            ("hack squat", .legs),
            ("hip thrust", .legs),
            ("face pull", .shoulders),
            ("rear delt", .shoulders),
            ("lateral raise", .shoulders),
            ("front raise", .shoulders),
            ("overhead press", .shoulders),
            ("shoulder press", .shoulders),
            ("arnold press", .shoulders),
            ("chest fly", .chest),
            ("pec deck", .chest),
            ("chest press", .chest),
            ("push up", .chest),
            ("push-up", .chest),
            ("pushup", .chest),
            ("skullcrusher", .arms),
            ("tricep", .arms),
            ("triceps", .arms),
            ("bicep", .arms),
            ("hammer curl", .arms),
            ("concentration curl", .arms),
            ("wrist curl", .arms),
            ("farmers walk", .legs),
            ("farmer", .legs),
            ("treadmill", .cardio),
            ("rowing machine", .cardio),
            ("assault bike", .cardio),
            ("ski erg", .cardio),
            ("elliptical", .cardio),
            ("jump rope", .cardio),
            ("deadlift", .back),
            ("pull up", .back),
            ("pull-up", .back),
            ("pullup", .back),
            ("chin up", .back),
            ("chin-up", .back),
            ("pulldown", .back),
            ("low row", .back),
            ("cable row", .back),
            ("seated row", .back),
            ("bent over row", .back),
            ("shrug", .back),
            ("iso-lateral row", .back),
            ("squat", .legs),
            ("lunge", .legs),
            ("leg curl", .legs),
            ("leg extension", .legs),
            ("calf raise", .legs),
            ("hip abduction", .legs),
            ("hip adduction", .legs),
            ("smith machine squat", .legs),
            ("smith machine bench", .chest),
            ("bench press", .chest),
            ("bench", .chest),
            ("fly", .chest),
            ("crossover", .chest),
            ("dip", .chest),
            ("curl", .arms),
            ("row", .back),
            ("press", .chest),
            ("plank", .core),
            ("hanging leg raise", .core),
            ("leg raise", .core),
            ("crunch", .core),
            ("ab wheel", .core),
            ("bike", .cardio),
        ]

        for (needle, bucket) in rules where h.contains(needle) {
            return bucket
        }

        if h.contains("press") && (h.contains("shoulder") || h.contains("ohp") || h.contains("overhead")) {
            return .shoulders
        }
        if h.contains("press") && h.contains("leg") { return .legs }

        return .unknown
    }

    /// True if any secondary muscle label maps to the same coarse bucket as `other`.
    static func secondaryJSONMatchesBucket(_ json: String?, bucket other: ExerciseMuscleBucket) -> Bool {
        guard other != .unknown, let json, let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return false }
        for s in arr {
            let k = s.lowercased()
            let bOpt = coarseBucketFromStoredSlug(k) ?? bucketFromMuscleLabel(s)
            if bOpt == other { return true }
        }
        return false
    }
}
