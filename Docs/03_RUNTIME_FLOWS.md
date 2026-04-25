# Runtime Flows and State Rules

## Workout lifecycle
1. User starts a workout.
2. App creates a WorkoutSession in status `active`.
3. App creates or restores ActiveWorkoutState.
4. User adds exercises.
5. Each added exercise creates a WorkoutSessionExercise row with display order.
6. User logs sets inline.
7. A set becomes canonical only when it has meaningful data; UI may show draft rows separately.
8. Tapping checkmark marks the set `completed`, stamps `completed_at`, updates caches, and starts or replaces the rest timer for that exercise.
9. User finishes workout.
10. App sets session status to `completed`, stamps `ended_at`, ends any active timer, refreshes caches, and persists history snapshots.

## Recovery flow
- On launch, if a workout session has status `active`, load it.
- If it has been inactive for a long threshold, mark it recoverable/stale and prompt:
  - Resume
  - Finish now
  - Discard
- Timer reconstruction is based on stored timestamps, not on memory-only countdown state.

## Rest timer rules
- Timer starts only on set completion.
- Timer belongs to the exercise context, not the whole workout globally.
- If the user completes another set before the timer ends, replace the current timer with the new one.
- Editing a completed set does not restart timer automatically.
- Manual adjustments change current timer end time and create a timer event.
- Finishing a workout ends the timer.

## Previous-value matching
Preferred matching order:
1. same exercise
2. same set-type bucket when possible
3. same working-set ordinal when possible
4. most recent completed set fallback

Notes:
- Warmups should not displace working-set comparisons unless there is no better match.
- Previous values are display data, not canonical persisted row fields.

## Editing completed workouts
- Completed workouts remain editable.
- Editing a historical workout should recalculate:
  - workout totals cache
  - personal records
  - exercise history snapshot
- Historical edits should not reopen the workout into `active` unless the user explicitly resumes it.
