PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS exercise (
    id TEXT PRIMARY KEY,
    canonical_name TEXT NOT NULL,
    display_name TEXT NOT NULL,
    exercise_mode TEXT NOT NULL CHECK (exercise_mode IN ('weight_reps', 'bodyweight_reps', 'duration', 'distance_duration')),
    equipment_type TEXT,
    primary_muscle_group TEXT,
    secondary_muscle_groups_json TEXT NOT NULL DEFAULT '[]',
    is_custom INTEGER NOT NULL DEFAULT 0,
    sort_name TEXT NOT NULL,
    instruction_text TEXT,
    gif_url TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);

CREATE TABLE IF NOT EXISTS exercise_alias (
    id TEXT PRIMARY KEY,
    exercise_id TEXT NOT NULL REFERENCES exercise(id) ON DELETE CASCADE,
    alias TEXT NOT NULL,
    normalized_alias TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_exercise_alias_unique
ON exercise_alias(exercise_id, normalized_alias);

CREATE TABLE IF NOT EXISTS workout_session (
    id TEXT PRIMARY KEY,
    title TEXT,
    notes TEXT,
    started_at TEXT NOT NULL,
    ended_at TEXT,
    status TEXT NOT NULL CHECK (status IN ('active', 'paused', 'completed', 'discarded')),
    source TEXT NOT NULL DEFAULT 'manual',
    total_duration_seconds_cache INTEGER,
    total_volume_kg_cache REAL NOT NULL DEFAULT 0,
    total_set_count_cache INTEGER NOT NULL DEFAULT 0,
    total_rep_count_cache INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_workout_session_status
ON workout_session(status, started_at DESC);

CREATE TABLE IF NOT EXISTS workout_block (
    id TEXT PRIMARY KEY,
    workout_session_id TEXT NOT NULL REFERENCES workout_session(id) ON DELETE CASCADE,
    block_type TEXT NOT NULL CHECK (block_type IN ('superset', 'circuit', 'giant_set')),
    display_order INTEGER NOT NULL,
    external_superset_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS workout_session_exercise (
    id TEXT PRIMARY KEY,
    workout_session_id TEXT NOT NULL REFERENCES workout_session(id) ON DELETE CASCADE,
    exercise_id TEXT NOT NULL REFERENCES exercise(id),
    block_id TEXT REFERENCES workout_block(id) ON DELETE SET NULL,
    display_order INTEGER NOT NULL,
    notes TEXT,
    exercise_mode TEXT NOT NULL CHECK (exercise_mode IN ('weight_reps', 'bodyweight_reps', 'duration', 'distance_duration')),
    target_rest_seconds INTEGER,
    is_collapsed INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_workout_session_exercise_session_order
ON workout_session_exercise(workout_session_id, display_order);

CREATE TABLE IF NOT EXISTS set_entry (
    id TEXT PRIMARY KEY,
    workout_session_exercise_id TEXT NOT NULL REFERENCES workout_session_exercise(id) ON DELETE CASCADE,
    logged_exercise_id TEXT REFERENCES exercise(id),
    set_index INTEGER NOT NULL,
    set_type TEXT NOT NULL CHECK (set_type IN ('warmup', 'normal', 'drop_set', 'failure', 'assisted', 'bodyweight', 'timed', 'distance')),
    status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'completed', 'skipped')),
    weight_kg REAL,
    reps INTEGER,
    distance_km REAL,
    duration_seconds INTEGER,
    rpe REAL,
    rir REAL,
    note TEXT,
    bodyweight_kg_snapshot REAL,
    assistance_weight_kg REAL,
    completed_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    UNIQUE(workout_session_exercise_id, set_index)
);

CREATE INDEX IF NOT EXISTS idx_set_entry_exercise_order
ON set_entry(workout_session_exercise_id, set_index);

CREATE INDEX IF NOT EXISTS idx_set_entry_completed
ON set_entry(status, completed_at DESC);

CREATE TABLE IF NOT EXISTS active_workout_state (
    workout_session_id TEXT PRIMARY KEY REFERENCES workout_session(id) ON DELETE CASCADE,
    current_workout_session_exercise_id TEXT REFERENCES workout_session_exercise(id) ON DELETE SET NULL,
    current_set_entry_id TEXT REFERENCES set_entry(id) ON DELETE SET NULL,
    focused_field TEXT,
    paused_at TEXT,
    autosave_revision INTEGER NOT NULL DEFAULT 0,
    recovery_state TEXT NOT NULL CHECK (recovery_state IN ('active', 'stale', 'recoverable')),
    last_opened_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS rest_timer_state (
    id TEXT PRIMARY KEY,
    workout_session_id TEXT NOT NULL REFERENCES workout_session(id) ON DELETE CASCADE,
    workout_session_exercise_id TEXT REFERENCES workout_session_exercise(id) ON DELETE SET NULL,
    source_set_entry_id TEXT REFERENCES set_entry(id) ON DELETE SET NULL,
    state TEXT NOT NULL CHECK (state IN ('idle', 'running', 'paused', 'completed', 'skipped')),
    started_at TEXT,
    paused_at TEXT,
    ends_at TEXT,
    remaining_at_pause_seconds INTEGER,
    default_duration_seconds INTEGER NOT NULL DEFAULT 0,
    user_adjusted_seconds INTEGER NOT NULL DEFAULT 0,
    auto_started INTEGER NOT NULL DEFAULT 1,
    last_action_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rest_timer_state_session
ON rest_timer_state(workout_session_id, last_action_at DESC);

CREATE TABLE IF NOT EXISTS rest_timer_event (
    id TEXT PRIMARY KEY,
    rest_timer_state_id TEXT NOT NULL REFERENCES rest_timer_state(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN ('started', 'paused', 'resumed', 'skipped', 'adjusted', 'completed', 'stopped')),
    timestamp TEXT NOT NULL,
    delta_seconds INTEGER,
    source TEXT NOT NULL CHECK (source IN ('auto', 'manual')),
    note TEXT
);

CREATE INDEX IF NOT EXISTS idx_rest_timer_event_timer
ON rest_timer_event(rest_timer_state_id, timestamp);

CREATE TABLE IF NOT EXISTS workout_template (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    notes TEXT,
    folder_name TEXT,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);

CREATE TABLE IF NOT EXISTS workout_template_exercise (
    id TEXT PRIMARY KEY,
    workout_template_id TEXT NOT NULL REFERENCES workout_template(id) ON DELETE CASCADE,
    exercise_id TEXT NOT NULL REFERENCES exercise(id),
    block_key TEXT,
    display_order INTEGER NOT NULL,
    target_set_count INTEGER,
    target_rep_min INTEGER,
    target_rep_max INTEGER,
    target_weight_kg REAL,
    target_duration_seconds INTEGER,
    target_distance_km REAL,
    default_set_type TEXT,
    default_rest_seconds INTEGER,
    notes TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_template_exercise_order
ON workout_template_exercise(workout_template_id, display_order);

CREATE TABLE IF NOT EXISTS personal_record (
    id TEXT PRIMARY KEY,
    exercise_id TEXT NOT NULL REFERENCES exercise(id),
    metric_type TEXT NOT NULL CHECK (metric_type IN ('max_weight', 'best_estimated_1rm', 'best_set_volume', 'best_session_volume', 'max_reps_at_weight')),
    metric_value REAL NOT NULL,
    source_set_entry_id TEXT REFERENCES set_entry(id) ON DELETE SET NULL,
    source_workout_session_id TEXT REFERENCES workout_session(id) ON DELETE SET NULL,
    achieved_at TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_personal_record_exercise_metric
ON personal_record(exercise_id, metric_type, achieved_at DESC);

CREATE TABLE IF NOT EXISTS exercise_history_snapshot (
    exercise_id TEXT PRIMARY KEY REFERENCES exercise(id) ON DELETE CASCADE,
    last_performed_at TEXT,
    last_workout_session_id TEXT REFERENCES workout_session(id) ON DELETE SET NULL,
    last_completed_set_summary_json TEXT,
    best_weight_kg REAL,
    best_estimated_1rm_kg REAL,
    lifetime_volume_kg REAL NOT NULL DEFAULT 0,
    completed_set_count INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL
);

-- Optional future tables for mirroring and AI. Keep them out of MVP implementation if needed.
CREATE TABLE IF NOT EXISTS remote_sync_state (
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    sync_state TEXT NOT NULL CHECK (sync_state IN ('local_only', 'pending_upload', 'synced', 'pending_delete')),
    last_synced_at TEXT,
    remote_revision TEXT,
    PRIMARY KEY (entity_type, entity_id)
);

CREATE TABLE IF NOT EXISTS coach_recommendation (
    id TEXT PRIMARY KEY,
    scope TEXT NOT NULL CHECK (scope IN ('session', 'intra_session')),
    workout_session_id TEXT REFERENCES workout_session(id) ON DELETE CASCADE,
    workout_session_exercise_id TEXT REFERENCES workout_session_exercise(id) ON DELETE CASCADE,
    set_entry_id TEXT REFERENCES set_entry(id) ON DELETE SET NULL,
    recommendation_type TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    confidence REAL,
    model_version TEXT,
    generated_at TEXT NOT NULL,
    acted_on_at TEXT,
    dismissed_at TEXT
);
