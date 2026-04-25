# Current Hevy Check (as of 2026-04-25)

Purpose: give Cursor factual current-product context so the clone app tracks the right behavior.

## Verified current facts
- Hevy is currently listed on the App Store for iPhone, iPad, Apple Watch, and iMessage.
- The App Store listing explicitly mentions Live Activity on the lock screen and Dynamic Island support.
- Hevy's current logging features include fast set-based workout logging, routines/planner support, custom exercises, automatic rest timers, 1RM calculations, graphs, and exercise history.
- Hevy's rest timer is configured per exercise, appears below the custom note section, triggers when a set is marked complete, and can be adjusted in 15-second increments during a workout.
- Hevy's exercise library currently advertises 400+ exercises with filters and custom exercises.
- Custom exercises include fields like image/video, equipment, primary/secondary muscles, and exercise type. The exercise type cannot be edited after save.
- Hevy can export workout data and measurement data from the app.
- Official CSV import is only for Strong exports in English; Hevy does not officially re-import its own workout export format.
- Hevy allows manually logging previous workouts by creating a workout, finishing it, and then adjusting the saved date/time/duration.
- Hevy supports routines that can be created, copied, imported from the library, and shared.

## Design implications for this project
- Mirror the active workout flow, not the export shape.
- Treat the export CSV as an interchange format and migration source only.
- Build a real exercise directory with canonical metadata and aliases.
- Support Dynamic Island and Live Activity as first-class surfaces.

## Sources checked
- App Store listing for Hevy
- Hevy help center articles on exercise library, import/export, previous workouts
- Hevy feature pages for rest timer, exercise library, and routines
