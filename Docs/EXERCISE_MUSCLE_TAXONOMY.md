# Exercise muscle taxonomy (Loggy)

`exercise.primary_muscle_group` is a single **slug** string. `exercise.secondary_muscle_groups_json` is a JSON array of slug strings.

These slugs are used for replacement suggestions, future volume-by-muscle planning, and coach features. They align loosely with common open datasets (e.g. free-exercise-db muscle names) and are normalized in app logic to coarse **buckets** for matching.

## Canonical slugs (v1)

| Slug | Typical meaning |
|------|------------------|
| `chest` | Pectorals |
| `upper back` | Mid-back / rhomboids |
| `lats` | Latissimus dorsi |
| `lower back` | Erector spinae / lumbar |
| `traps` | Trapezius |
| `shoulders` | Deltoids |
| `biceps` | Biceps brachii |
| `triceps` | Triceps brachii |
| `forearms` | Brachioradialis, grip, wrist flexors/extensors |
| `quadriceps` | Quads |
| `hamstrings` | Hamstrings |
| `glutes` | Glute max/med/min |
| `calves` | Gastrocnemius / soleus |
| `abs` | Rectus abdominis / obliques (core) |
| `hip flexors` | Iliopsoas etc. |
| `adductors` | Adductor group |
| `abductors` | Glute med / TFL |
| `cardio` | General conditioning / mixed |
| `neck` | Neck |

Custom exercises may use any slug; UI can later constrain picks to this list.

## Bundled map

[`App/Resources/exercise_muscle_map.json`](../App/Resources/exercise_muscle_map.json) maps Hevy-style `canonical_name` keys to `{ "primary", "secondaries" }`. A GRDB migration applies it to existing `exercise` rows. Regenerate or extend via `Scripts/build_exercise_muscle_map.py` (optional helper).

## Licensing note

In-repo muscle strings are **curated** for Loggy. External datasets (e.g. [free-exercise-db](https://github.com/yuhonas/free-exercise-db), Unlicense) may be used as **reference** when extending the map; do not copy large proprietary catalogs without a license.
