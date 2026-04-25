# Cursor Facts

These are the core facts Composer should treat as stable project constraints.

## Product facts
- This app is for one user only.
- The target behavior is a Hevy-like active workout lifecycle.
- The app should feel iPhone-first, with support for Dynamic Island and Live Activity.
- The visual system should use modern glass/material containers but keep logging surfaces solid and legible.

## Data facts
- The set is the atomic source of truth.
- Internal storage is normalized; export CSV is not the internal model.
- Every workout contains ordered exercises-in-session.
- Every exercise-in-session contains ordered set entries.
- Supersets or grouped movements belong to workout-time block entities, not global exercise metadata.
- “Previous” is derived from history, not stored inline.

## Runtime facts
- There can be only one active workout at a time.
- Rest timers are per exercise and start when a set is marked complete.
- Active workout state must survive backgrounding and relaunch.
- Completed workouts remain editable.

## Sync facts
- Core app behavior must not depend on network.
- Remote mirroring is optional and later.
- If mirroring is added, use simple personal-account semantics and last-write-wins.

## AI facts
- AI is layered on top of the logging engine.
- Session Coach and Intra-Session Coach are separate systems.
- Live coaching is rules-based first, LLM-explained second.
