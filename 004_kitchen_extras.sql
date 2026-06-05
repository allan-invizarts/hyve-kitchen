-- ============================================================================
-- HYVE KITCHEN -- MIGRATION 004: KITCHEN EXTRAS
-- ============================================================================
-- Adds three independent improvements on top of V103 cookbook evolution:
--   1. Full version snapshots for recipe vars + outputs (cookbook_recipe_var
--      now only persists the CURRENT shape; we want history alongside the
--      python_body history that cookbook_recipe_version already keeps).
--   2. Per-system render-card theming via cookbook_system.render_theme_json.
--      Single column (TEXT, not JSONB) holding a small JSON document of
--      colours; SDK render.card consumes it.
--   3. correlation_id propagation across services. Adds the column on
--      kitchen_invocation so bridge -> cookbook -> kitchen -> UE traces
--      can be tied together by a single ID.
--
-- Apply with:
--   docker exec -i hyve-postgres psql -1 -U hyve_admin hyve_llm \
--     < hyve-blackbox/hyve-kitchen/migrations/004_kitchen_extras.sql
-- ============================================================================

BEGIN;


-- ============================================================================
-- BLOCK A: Pre-flight (require V103 to have landed)
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM schema_version WHERE version = 103) THEN
        RAISE EXCEPTION 'V103 (cookbook evolution) must be applied first. Apply 003_cookbook_evolution.sql, then re-run this.';
    END IF;
END $$;


-- ============================================================================
-- BLOCK B: cookbook_recipe_var_version (full per-version snapshot of vars)
-- ----------------------------------------------------------------------------
-- One row per (recipe_version_id, var_name) so a future operator can see
-- exactly which vars + validation rules a previous version had. Append-only.
-- ============================================================================
CREATE TABLE IF NOT EXISTS cookbook_recipe_var_version (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('RVV'),
    recipe_version_id VARCHAR(36) NOT NULL REFERENCES cookbook_recipe_version(id) ON DELETE CASCADE,

    var_name VARCHAR(120) NOT NULL,
    var_type VARCHAR(20) NOT NULL DEFAULT 'string',
    var_source VARCHAR(20) NOT NULL DEFAULT 'call_time',
    is_required INTEGER NOT NULL DEFAULT 1,
    default_value TEXT,
    val_format VARCHAR(20),
    val_min_length INTEGER,
    val_max_length INTEGER,
    val_min_value NUMERIC,
    val_max_value NUMERIC,
    val_pattern TEXT,
    san_trim_whitespace INTEGER NOT NULL DEFAULT 1,
    san_lowercase INTEGER NOT NULL DEFAULT 0,
    san_strip_html INTEGER NOT NULL DEFAULT 0,
    re_ask_if_missing INTEGER NOT NULL DEFAULT 0,
    re_ask_prompt TEXT,
    is_masked INTEGER NOT NULL DEFAULT 0,
    description TEXT NOT NULL,
    allowed_values_csv TEXT,                     -- comma-separated enum snapshot (string fmt only)

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.4',

    UNIQUE (recipe_version_id, var_name)
);

CREATE INDEX IF NOT EXISTS idx_cookbook_recipe_var_version_recipe_version_id
    ON cookbook_recipe_var_version(recipe_version_id);


-- ============================================================================
-- BLOCK C: cookbook_recipe_output_version (same idea for outputs)
-- ============================================================================
CREATE TABLE IF NOT EXISTS cookbook_recipe_output_version (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('ROV'),
    recipe_version_id VARCHAR(36) NOT NULL REFERENCES cookbook_recipe_version(id) ON DELETE CASCADE,

    output_key VARCHAR(120) NOT NULL,
    source_path TEXT NOT NULL,
    value_type VARCHAR(20) NOT NULL DEFAULT 'string',
    is_required INTEGER NOT NULL DEFAULT 0,
    description TEXT,
    display_label VARCHAR(120),

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.4',

    UNIQUE (recipe_version_id, output_key)
);

CREATE INDEX IF NOT EXISTS idx_cookbook_recipe_output_version_recipe_version_id
    ON cookbook_recipe_output_version(recipe_version_id);


-- ============================================================================
-- BLOCK D: cookbook_system.render_theme_json (per-system card theming)
-- ----------------------------------------------------------------------------
-- TEXT (not JSONB) per the "minimize JSONB" directive; small enough that
-- application-side JSON.parse on read is fine. Expected keys:
--     {
--         "banner_dark":   "#1565c0",
--         "banner_light":  "#e3f2fd",
--         "text_dark":     "#0d47a1",
--         "accent":        "#1976d2"
--     }
-- NULL means "use SDK default neutral theme".
-- ============================================================================
ALTER TABLE cookbook_system
    ADD COLUMN IF NOT EXISTS render_theme_json TEXT;


-- ============================================================================
-- BLOCK E: kitchen_invocation.correlation_id (cross-component tracing)
-- ============================================================================
ALTER TABLE kitchen_invocation
    ADD COLUMN IF NOT EXISTS correlation_id VARCHAR(36);

CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_correlation_id
    ON kitchen_invocation(correlation_id) WHERE correlation_id IS NOT NULL;


-- ============================================================================
-- BLOCK F: cookbook_event_trigger.correlation_id_template (optional;
-- lets a trigger override the default correlation_id propagation behaviour).
-- ============================================================================
ALTER TABLE cookbook_event_trigger
    ADD COLUMN IF NOT EXISTS correlation_id_template VARCHAR(120);


-- ============================================================================
-- BLOCK G: Comments
-- ============================================================================
COMMENT ON TABLE cookbook_recipe_var_version IS
    'Per-version snapshot of cookbook_recipe_var rows. Append-only history alongside cookbook_recipe_version.';
COMMENT ON TABLE cookbook_recipe_output_version IS
    'Per-version snapshot of cookbook_recipe_output rows. Append-only history.';
COMMENT ON COLUMN cookbook_system.render_theme_json IS
    'Optional per-system card theme as small JSON string (TEXT to honour minimize-JSONB). Keys: banner_dark, banner_light, text_dark, accent. NULL = SDK neutral default.';
COMMENT ON COLUMN kitchen_invocation.correlation_id IS
    'Cross-component trace ID. Bridge events carry it; cookbook RecipeContext forwards it; kitchen persists it here. Lets ops grep one ID across bridge_command_audit, kitchen_invocation, and downstream UE logs.';


-- ============================================================================
-- BLOCK H: schema_version
-- ============================================================================
-- Defensive: see 002/003 for the same pattern. Lets this migration run
-- in isolation.
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    description TEXT,
    applied_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO schema_version (version, description)
VALUES (
    104,
    'V104 (kitchen): cookbook_recipe_var_version + cookbook_recipe_output_version tables (full per-version snapshots), cookbook_system.render_theme_json column (per-system render-card theming), kitchen_invocation.correlation_id column (cross-component tracing), cookbook_event_trigger.correlation_id_template column.'
)
ON CONFLICT (version) DO NOTHING;


COMMIT;
