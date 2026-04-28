#!/usr/bin/env python3
"""
Optional helper: merge free-exercise-db style JSON with Loggy canonical names.

Usage (manual):
  curl -sL https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json -o /tmp/exercises.json
  python3 Scripts/build_exercise_muscle_map.py /tmp/exercises.json > App/Resources/exercise_muscle_map.json

The repo already ships a curated `exercise_muscle_map.json`; this script is for refreshing
from upstream when you intentionally want to reconcile names.
"""
from __future__ import annotations

import json
import sys


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: build_exercise_muscle_map.py <free-exercise-db exercises.json>", file=sys.stderr)
        sys.exit(1)
    with open(sys.argv[1], encoding="utf-8") as f:
        exercises = json.load(f)
    out: dict[str, dict] = {}
    for ex in exercises:
        name = (ex.get("name") or "").strip()
        if not name:
            continue
        key = name.lower()
        prim = ex.get("primaryMuscles") or []
        sec = ex.get("secondaryMuscles") or []
        if not prim:
            continue
        out[key] = {"primary": prim[0].lower(), "secondaries": [s.lower() for s in sec]}
    json.dump(out, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
