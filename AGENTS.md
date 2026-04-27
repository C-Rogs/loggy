# Project Instructions

## Product goal
Build a single-user iPhone-first workout logging app that closely mirrors Hevy's active workout lifecycle while staying local-first and extensible.

## Non-negotiable product rules
- One user only. Do not design for teams, sharing, or multi-user collaboration.
- The workout lifecycle must feel like Hevy: start workout, add exercises, log sets inline, tap checkmark to complete sets, auto-start rest timer, finish workout, keep history editable.
- The set is the source of truth. Do not store workouts as JSON blobs.
- Use a normalized data model centered on workout sessions, exercises-in-session, and set entries.
- Treat the CSV export as an import/export format, not the internal storage shape.
- Preserve a strong exercise identity model with canonical exercises plus aliases.
- Make the app local-first. All user actions should succeed without network.
- Remote mirroring is optional and later. If added, prefer simple last-write-wins over complex conflict systems.

## Tech direction
- Use SwiftUI.
- Use a repository/service architecture.
- Persist with SQLite via GRDB unless explicitly changed later.
- Keep business logic out of views.
- Use small testable services for timers, history matching, PR calculation, and AI coaching.

## UX rules
- Logging speed is more important than decorative UI.
- Inline editing only for normal set entry.
- No modal flow for basic set edits.
- A completed set can still be edited later.
- Glass/material effects belong on container surfaces such as headers, sheets, timer bars, and summary bars.
- Use solid, high-contrast surfaces for set rows and numeric inputs.
- Dynamic Island and Live Activity are projections of workout state, not their own source of truth.

## Hevy-like timer rules
- Rest timer starts only when a set is marked completed.
- Editing a completed set does not restart the timer.
- Completing another set replaces the active timer.
- Timer state must be timestamp-driven so it survives backgrounding and relaunch.
- Finishing a workout ends any running timer immediately.

## History and “Previous” rules
- “Previous” is derived from prior completed workouts.
- Prefer matching same exercise, same set type bucket, same working-set ordinal.
- Fall back to the most recent completed set for that exercise.
- Never persist previous values as primary row data.

## AI coach rules
- Split coaching into two systems:
  - Session Coach: slower planning/review recommendations outside or after the workout.
  - Intra-Session Coach: fast live suggestions after a set completes.
- Intra-Session Coach must be rules-driven first. LLM text is only for explanation.
- AI recommendations are advisory and stored separately from canonical workout data.

## Delivery rules for Composer
- Build in small milestones.
- Prefer creating real source files over giant speculative docs.
- Keep files readable and modular.
- When schema changes, update docs and code together.
- After each logical code change: **commit** with a focused message (easy to revert), then **build** the Loggy scheme for the iPhone Simulator and **install + launch** the app on the booted simulator (verify it runs). Use `xcodebuild` plus `xcrun simctl` install/launch with bundle id `com.loggy.app` when automation is needed.
