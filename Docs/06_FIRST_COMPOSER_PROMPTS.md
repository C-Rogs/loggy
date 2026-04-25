# First Composer Prompts

Use these prompts in order.

## Prompt 1 — bootstrap the foundation
Read `AGENTS.md`, all files in `.cursor/rules/`, and `Docs/01_PROJECT_FACTS.md`, `Docs/02_PRODUCT_SPEC.md`, `Docs/03_RUNTIME_FLOWS.md`, and `Docs/04_DATABASE_SCHEMA.sql`.

Then create the initial Swift project structure for this app inside `App/` with:
- domain models
- core enums
- repository protocols
- GRDB database manager and migrations from the schema
- stub services for timer, previous-value matching, and workout calculations
- no UI yet beyond minimal app entry

## Prompt 2 — build active workout logging
Using the project docs and rules, implement the Active Workout screen and view model.

Requirements:
- exercise cards
- inline set rows
- add set
- edit weight/reps inline
- one-tap completion
- auto-start rest timer on completion
- summary strip
- no modal flow for basic set editing

## Prompt 3 — add recovery and timer behavior
Implement active workout recovery and timestamp-driven rest timer behavior.

Requirements:
- restore active workout on relaunch
- support Resume / Finish / Discard for recoverable workouts
- ensure editing a completed set does not restart the timer
- finishing a workout ends timer and persists final caches

## Prompt 4 — add history and previous values
Implement workout history, exercise history, and the Previous column matching logic.

Requirements:
- editable completed workouts
- history queries from normalized tables
- previous matching based on the documented matching order
- rebuild cache functions for historical edits

## Prompt 5 — add exercise directory and templates
Implement the exercise directory and template system.

Requirements:
- canonical exercise list
- aliases
- custom exercises
- exercise picker search and filters
- templates and template exercises with default rest settings

## Prompt 6 — add Dynamic Island and Live Activity
Implement a Live Activity backed by workout state.

Requirements:
- elapsed workout time
- current exercise name
- active rest countdown
- keep it glanceable and derived from canonical state

## Prompt 7 — add import support for Hevy export
Implement a CSV import flow for the Hevy export format described in `Docs/05_IMPORT_MAPPING.md`.

Requirements:
- parse the export format reliably
- map to normalized tables
- avoid duplicate imports
- create custom exercises and aliases when needed

## Prompt 8 — add AI hooks only after the core app works
Implement storage and service boundaries for Session Coach and Intra-Session Coach.

Requirements:
- store recommendations separately from workout truth
- rules-first intra-session analysis
- no direct AI mutation of canonical workout rows
