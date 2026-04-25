# Product Spec

## Goal
Build a production-quality personal workout logger that mirrors Hevy's session flow and becomes a stable base for future features such as templates, remote mirroring, and two AI coach modes.

## MVP scope
- Start an empty workout or start from a template
- Add, remove, reorder exercises in an active workout
- Log sets inline with one-tap completion
- Auto-start per-exercise rest timer on set completion
- Show a "Previous" column derived from workout history
- Finish a workout and save it to history
- Re-open and edit completed workouts
- Browse a full exercise directory with custom exercises
- Support Live Activity / Dynamic Island for the active workout

## Core screens
1. Home / Workout History
2. Active Workout
3. Exercise Picker / Directory
4. Exercise Detail / History
5. Templates
6. Settings

## Active Workout screen
### Header
- workout title
- elapsed time
- finish action
- overflow menu

### Summary strip
- elapsed time
- total volume
- total completed sets
- optional total reps

### Exercise cards
Each card contains:
- exercise name
- optional exercise notes
- optional rest target control
- set table
- add set button
- overflow actions

### Set table columns
For weight + reps exercises:
- set label
- previous
- weight
- reps
- done

For timed exercises:
- set label
- previous
- duration
- done

For distance-based exercises:
- set label
- previous
- distance
- duration
- done

## Key behaviors
- Add Set clones the most recent set for that exercise when possible.
- Tapping done completes the set, stamps completion time, starts rest timer, refreshes workout totals, and updates previous/PR data.
- Editing a completed set does not automatically restart rest timer.
- Deleting a set reindexes set order for that exercise.
- Warmup and working sets are distinct first-class types.

## Non-goals for MVP
- social features
- team accounts
- complex sync conflict UI
- automatic coaching changes without user confirmation
