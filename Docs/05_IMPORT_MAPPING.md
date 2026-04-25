# Hevy Export Mapping

This project should support importing the user's Hevy workout export CSV, but it must not confuse that with the internal runtime model.

## Current export columns observed
- title
- start_time
- end_time
- description
- exercise_title
- superset_id
- exercise_notes
- set_index
- set_type
- weight_kg
- reps
- distance_km
- duration_seconds
- rpe

## Mapping rules
### WorkoutSession
- `title` -> `workout_session.title`
- `description` -> `workout_session.notes`
- `start_time` -> `workout_session.started_at`
- `end_time` -> `workout_session.ended_at`
- imported sessions should usually land in `completed` status

### Exercise
- `exercise_title` -> resolve to canonical `exercise.display_name`
- if no match exists, create a custom exercise and also add an alias from the imported name

### WorkoutBlock
- `superset_id` -> `workout_block.external_superset_id`
- create a block only if the field is non-empty

### WorkoutSessionExercise
- one row per exercise occurrence inside a workout
- `exercise_notes` -> `workout_session_exercise.notes`
- preserve display order from source row order
- repeated exercises in the same workout must create separate rows when they are distinct occurrences

### SetEntry
- `set_index` -> `set_entry.set_index`
- `set_type` -> `set_entry.set_type`
- `weight_kg` -> `set_entry.weight_kg`
- `reps` -> `set_entry.reps`
- `distance_km` -> `set_entry.distance_km`
- `duration_seconds` -> `set_entry.duration_seconds`
- `rpe` -> `set_entry.rpe`
- imported rows should become `status = completed`

## Import constraints
- Parse dates using the export's local timestamp format.
- Preserve source ordering.
- Use import batches to avoid accidental duplicates.
- Never rely on the CSV for runtime-only state such as:
  - active timer state
  - focused field
  - recovery state
  - live activity state
  - draft rows
