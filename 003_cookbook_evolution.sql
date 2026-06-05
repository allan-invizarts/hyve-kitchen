-- ============================================================================
-- HYVE KITCHEN -- MIGRATION 003: COOKBOOK EVOLUTION
-- ============================================================================
-- Status: DRAFT 2026-05-27 -- PENDING REVIEW. Do not apply until approved.
--
-- This migration delivers the kitchen/cookbook/recipe vision:
--   1. RENAME kitchen_recipe / kitchen_recipe_version / kitchen_recipe_tag
--      to cookbook_recipe / cookbook_recipe_version / cookbook_recipe_tag so
--      the word "cookbook" (storage) is distinct from "kitchen" (execution).
--   2. ADD system + module organizational hierarchy
--      (cookbook_system -> cookbook_module -> cookbook_recipe).
--   3. ADD credential management
--      (cookbook_auth_profile -> cookbook_global_var).
--   4. ADD per-var + per-output normalized tables to replace the
--      arguments_schema / returns_schema / output_map JSONB columns, per
--      the house-style "minimize JSONB" directive. Validation rules,
--      sanitization flags, and LLM re-ask prompts are first-class columns.
--   5. ADD cookbook_template -- DB-stored Python templates that get
--      rendered into cookbook_recipe.python_body. One template can spawn
--      many recipes (e.g. odoo_crud_create template -> odoo_create_lead,
--      odoo_create_contact, odoo_create_opportunity recipes).
--   6. ADD behavior flags to cookbook_recipe (is_read_only, is_getset,
--      is_batch, is_chainable, expected_duration_ms, masked_fields_via_var)
--      so the LLM can reason about which recipes are safe to retry / cache /
--      batch / chain.
--   7. NORMALIZE kitchen_invocation -- replace arguments / result / metadata
--      JSONB with row tables (kitchen_invocation_var, kitchen_invocation_output,
--      kitchen_invocation_validation_error) for queryability and indexing.
--
-- LIVE-DB MIGRATION (one-shot before applying this file):
--   This migration assumes 001_kitchen_schema.sql + 002_kitchen_async_jobs.sql
--   have already been applied (kitchen_recipe / kitchen_invocation exist).
--   For a fresh DB, run those two first, then this one.
--
--   For an existing DB with data, the RENAME blocks below are idempotent
--   (wrapped in DO $$ ... EXISTS checks). The DROP COLUMN blocks for the
--   old JSONB columns MIGRATE the data into the new row tables before
--   dropping -- see Block H. Operator should:
--     1. BACKUP the database (pg_dump). Do not skip.
--     2. Apply this file in a single transaction (psql -1 -f).
--     3. Verify SELECT version FROM schema_version returns 103.
--     4. Re-publish the cookbook tool manifest so /v1/tools rebuilds from
--        cookbook_recipe_var rows instead of the dropped arguments_schema.
--
-- Apply with:
--   docker exec -i hyve-postgres psql -1 -U hyve_admin hyve_llm \
--     < hyve-blackbox/hyve-kitchen/migrations/003_cookbook_evolution.sql
-- ============================================================================

BEGIN;


-- ============================================================================
-- BLOCK A: PRE-FLIGHT CHECKS
-- ============================================================================
-- Hard requirements before V103 can run. As of 2026-05-27, the kitchen
-- schema is STANDALONE -- 001_kitchen_schema.sql's Block 0 bootstrap
-- creates generate_custom_guid() + schema_version + a minimal
-- subscription table if they're missing. So the only thing V103 strictly
-- needs is that 001 has been applied first (kitchen_recipe / cookbook_recipe
-- exists).
--
-- The block is one-shot inside DO $$ so a failed check leaves NO partial
-- state behind (transaction rolls back). Use the migration runner if you
-- want the full sequencing managed for you:
--     python3 hyve-blackbox/devops/scripts/migrate.py --dsn <dsn> --apply
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'generate_custom_guid') THEN
        RAISE EXCEPTION 'V103 PREREQ MISSING: generate_custom_guid() function not found. This normally comes from 001_kitchen_schema.sql Block 0 (standalone bootstrap) OR from hyve-blackbox/devops/postgres/01-init-schema.sql. Apply 001_kitchen_schema.sql first.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'subscription'
    ) THEN
        RAISE EXCEPTION 'V103 PREREQ MISSING: subscription table not found. As of 2026-05-27, 001_kitchen_schema.sql Block 0 creates a minimal subscription stub for standalone mode. Re-apply 001_kitchen_schema.sql -- if it errors there, the standalone bootstrap is failing for a separate reason.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'kitchen_recipe'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'cookbook_recipe'
    ) THEN
        RAISE EXCEPTION 'V103 PREREQ MISSING: neither kitchen_recipe nor cookbook_recipe table found. Apply hyve-blackbox/hyve-kitchen/migrations/001_kitchen_schema.sql first.';
    END IF;
END $$;


-- ============================================================================
-- BLOCK B: RENAME kitchen_recipe* -> cookbook_recipe*
-- ----------------------------------------------------------------------------
-- Foreign keys auto-track table renames in Postgres. The kitchen_invocation
-- table's recipe_id FK continues to point at the renamed cookbook_recipe.
-- Indexes are renamed explicitly so naming convention stays
-- idx_<table>_<column>.
-- ============================================================================
DO $$
BEGIN
    -- kitchen_recipe -> cookbook_recipe
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema = 'public' AND table_name = 'kitchen_recipe') THEN
        ALTER TABLE kitchen_recipe RENAME TO cookbook_recipe;
    END IF;

    -- kitchen_recipe_version -> cookbook_recipe_version
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema = 'public' AND table_name = 'kitchen_recipe_version') THEN
        ALTER TABLE kitchen_recipe_version RENAME TO cookbook_recipe_version;
    END IF;

    -- kitchen_recipe_tag -> cookbook_recipe_tag
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema = 'public' AND table_name = 'kitchen_recipe_tag') THEN
        ALTER TABLE kitchen_recipe_tag RENAME TO cookbook_recipe_tag;
    END IF;
END $$;

-- Indexes (Postgres does not auto-rename indexes when their table is renamed).
ALTER INDEX IF EXISTS idx_kitchen_recipe_name             RENAME TO idx_cookbook_recipe_name;
ALTER INDEX IF EXISTS idx_kitchen_recipe_is_enabled       RENAME TO idx_cookbook_recipe_is_enabled;
ALTER INDEX IF EXISTS idx_kitchen_recipe_is_deleted       RENAME TO idx_cookbook_recipe_is_deleted;
ALTER INDEX IF EXISTS idx_kitchen_recipe_required_role    RENAME TO idx_cookbook_recipe_required_role;
ALTER INDEX IF EXISTS idx_kitchen_recipe_embedding        RENAME TO idx_cookbook_recipe_embedding;
ALTER INDEX IF EXISTS idx_kitchen_recipe_version_recipe_id RENAME TO idx_cookbook_recipe_version_recipe_id;
ALTER INDEX IF EXISTS idx_kitchen_recipe_tag_tag          RENAME TO idx_cookbook_recipe_tag_tag;

-- FK constraint on cookbook_recipe.current_version_id was named
-- fk_kitchen_recipe_current_version. Rename to match the new table.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_kitchen_recipe_current_version'
    ) THEN
        ALTER TABLE cookbook_recipe
            RENAME CONSTRAINT fk_kitchen_recipe_current_version
            TO fk_cookbook_recipe_current_version;
    END IF;
END $$;


-- ============================================================================
-- BLOCK C: cookbook_system + cookbook_module (organizational hierarchy)
-- ----------------------------------------------------------------------------
-- Two-level taxonomy so the LLM and the docs UI can navigate by integration
-- target rather than only by tag. Example rows:
--   cookbook_system: odoo, googlemaps, weather, openai, twilio, ...
--   cookbook_module under odoo: crm, inventory, sale, hr, calendar, ...
--   cookbook_module under googlemaps: places, directions, distance_matrix
-- ============================================================================
CREATE TABLE IF NOT EXISTS cookbook_system (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('CSY'),

    system_label VARCHAR(80) NOT NULL UNIQUE,            -- snake_case, e.g. "odoo"
    display_name VARCHAR(120) NOT NULL,                  -- "Odoo ERP"
    description TEXT,                                    -- one-paragraph overview
    homepage_url TEXT,                                   -- vendor docs / homepage
    icon_filename VARCHAR(120),                          -- e.g. "odoo.svg" (served from /assets/icons)

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.3'
);

CREATE INDEX IF NOT EXISTS idx_cookbook_system_system_label ON cookbook_system(system_label);
CREATE INDEX IF NOT EXISTS idx_cookbook_system_is_deleted   ON cookbook_system(is_deleted);


CREATE TABLE IF NOT EXISTS cookbook_module (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('CMD'),
    system_id VARCHAR(36) NOT NULL REFERENCES cookbook_system(id) ON DELETE RESTRICT,

    module_label VARCHAR(80) NOT NULL,                   -- snake_case, e.g. "crm"
    display_name VARCHAR(120) NOT NULL,                  -- "Customer Relationship Management"
    description TEXT,

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.3',

    UNIQUE (system_id, module_label)
);

CREATE INDEX IF NOT EXISTS idx_cookbook_module_system_id    ON cookbook_module(system_id);
CREATE INDEX IF NOT EXISTS idx_cookbook_module_module_label ON cookbook_module(module_label);
CREATE INDEX IF NOT EXISTS idx_cookbook_module_is_deleted   ON cookbook_module(is_deleted);


-- ============================================================================
-- BLOCK D: cookbook_auth_profile + cookbook_global_var (credentials)
-- ----------------------------------------------------------------------------
-- A recipe is bound to one auth_profile (e.g. "odoo_test", "odoo_prod").
-- Each auth_profile owns N global_var rows (one per env-style key).
-- Engine resolves global_vars at recipe-execution time and injects them
-- into the script's vars dict alongside call_time vars.
--
-- secret_values: var_value should be encrypted at rest. This migration
-- creates the columns; encryption layer is a follow-up (pgcrypto or
-- application-level). is_secret on the var marks rows for redaction.
-- ============================================================================
CREATE TABLE IF NOT EXISTS cookbook_auth_profile (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('CAP'),
    system_id VARCHAR(36) NOT NULL REFERENCES cookbook_system(id) ON DELETE RESTRICT,

    profile_label VARCHAR(80) NOT NULL,                  -- "odoo_test", "odoo_prod"
    display_name VARCHAR(120) NOT NULL,                  -- "Odoo - Test Instance"
    description TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,                -- 0 = profile disabled

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.3',

    UNIQUE (system_id, profile_label)
);

CREATE INDEX IF NOT EXISTS idx_cookbook_auth_profile_system_id    ON cookbook_auth_profile(system_id);
CREATE INDEX IF NOT EXISTS idx_cookbook_auth_profile_profile_label ON cookbook_auth_profile(profile_label);
CREATE INDEX IF NOT EXISTS idx_cookbook_auth_profile_is_active    ON cookbook_auth_profile(is_active);
CREATE INDEX IF NOT EXISTS idx_cookbook_auth_profile_is_deleted   ON cookbook_auth_profile(is_deleted);


CREATE TABLE IF NOT EXISTS cookbook_global_var (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('CGV'),
    auth_profile_id VARCHAR(36) NOT NULL REFERENCES cookbook_auth_profile(id) ON DELETE CASCADE,

    var_name VARCHAR(120) NOT NULL,                      -- "odoo_base_url"
    var_value TEXT NOT NULL,                             -- plaintext per 2026-05-27 decision (must be GUI-editable; restrict via min_edit_role)
    var_type VARCHAR(20) NOT NULL DEFAULT 'string',      -- string | int | bool | secret | url
    is_secret INTEGER NOT NULL DEFAULT 0,                -- redact in logs + UI display (still plaintext at rest)
    -- min_edit_role gates the hyve-admin GUI / API write paths. References
    -- the user table's role CHECK ('super_admin'|'admin'|'trainer'|'user'|'viewer').
    -- Default 'admin' means only admin and above can edit. Read access is
    -- never gated here (recipe execution always reads); is_secret controls
    -- whether the value is displayed in the UI even to those who can edit.
    min_edit_role VARCHAR(20) NOT NULL DEFAULT 'admin',
    description TEXT,
    expires_date TIMESTAMP,                              -- NULL = no expiry

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.3',

    UNIQUE (auth_profile_id, var_name),
    CONSTRAINT cookbook_global_var_min_edit_role_check
        CHECK (min_edit_role IN ('super_admin', 'admin', 'trainer', 'user', 'viewer'))
);

CREATE INDEX IF NOT EXISTS idx_cookbook_global_var_auth_profile_id ON cookbook_global_var(auth_profile_id);
CREATE INDEX IF NOT EXISTS idx_cookbook_global_var_var_name        ON cookbook_global_var(var_name);
CREATE INDEX IF NOT EXISTS idx_cookbook_global_var_is_secret       ON cookbook_global_var(is_secret);
CREATE INDEX IF NOT EXISTS idx_cookbook_global_var_min_edit_role   ON cookbook_global_var(min_edit_role);
CREATE INDEX IF NOT EXISTS idx_cookbook_global_var_is_deleted      ON cookbook_global_var(is_deleted);


-- ============================================================================
-- BLOCK E: cookbook_template (DB-stored recipe templates)
-- ----------------------------------------------------------------------------
-- A template is a Python source file with Jinja2-style placeholders that the
-- engine renders against (cookbook_recipe + cookbook_recipe_var + system +
-- module) metadata to produce a runnable cookbook_recipe.python_body.
--
-- Example: one "odoo_crud_create" template can spawn odoo_create_lead,
-- odoo_create_contact, odoo_create_opportunity recipes by binding it to
-- different odoo_model / vars combinations.
--
-- When a template changes, the engine can re-render every recipe that
-- references it (template_id) and bump the recipe version.
-- ============================================================================
CREATE TABLE IF NOT EXISTS cookbook_template (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('CTM'),
    system_id VARCHAR(36) REFERENCES cookbook_system(id) ON DELETE SET NULL,
    module_id VARCHAR(36) REFERENCES cookbook_module(id) ON DELETE SET NULL,

    template_label VARCHAR(120) NOT NULL UNIQUE,         -- "odoo_crud_create"
    display_name VARCHAR(255) NOT NULL,                  -- "Odoo Generic CREATE via JSON-RPC"
    description TEXT NOT NULL,

    template_text TEXT NOT NULL,                         -- Python source with {{ placeholders }}
    template_engine VARCHAR(20) NOT NULL DEFAULT 'jinja2',  -- jinja2 | format | none
    expected_signature VARCHAR(20) NOT NULL DEFAULT 'vars_dict',  -- vars_dict | kwargs

    -- Default behavior recipes derived from this template inherit. Each can
    -- be overridden per-recipe in cookbook_recipe.
    default_is_read_only INTEGER NOT NULL DEFAULT 0,
    default_is_getset INTEGER NOT NULL DEFAULT 0,
    default_is_batch INTEGER NOT NULL DEFAULT 0,
    default_is_chainable INTEGER NOT NULL DEFAULT 0,
    default_expected_duration_ms INTEGER,

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.3'
);

CREATE INDEX IF NOT EXISTS idx_cookbook_template_template_label ON cookbook_template(template_label);
CREATE INDEX IF NOT EXISTS idx_cookbook_template_system_id      ON cookbook_template(system_id);
CREATE INDEX IF NOT EXISTS idx_cookbook_template_module_id      ON cookbook_template(module_id);
CREATE INDEX IF NOT EXISTS idx_cookbook_template_is_deleted     ON cookbook_template(is_deleted);


-- ============================================================================
-- BLOCK F: cookbook_recipe_var + cookbook_recipe_var_allowed_value
-- ----------------------------------------------------------------------------
-- Replaces the cookbook_recipe.arguments_schema JSONB blob with one row
-- per variable. Validation rules, sanitization flags, re-ask prompts are
-- first-class columns. Allowed-value enumerations get their own child
-- table to honour the "no JSONB" directive.
--
-- The /v1/tools manifest is derived from these rows at request time (or
-- cached, with invalidation on UPDATE/INSERT/DELETE). cookbook_recipe no
-- longer stores arguments_schema separately.
-- ============================================================================
CREATE TABLE IF NOT EXISTS cookbook_recipe_var (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('CRV'),
    recipe_id VARCHAR(36) NOT NULL,                      -- FK added below after cookbook_recipe exists

    var_name VARCHAR(120) NOT NULL,                      -- snake_case, must match ^[a-z][a-z0-9_]*$
    var_type VARCHAR(20) NOT NULL DEFAULT 'string',      -- string | int | bool | decimal | date | array
    var_source VARCHAR(20) NOT NULL DEFAULT 'call_time', -- call_time | global_vars
    is_required INTEGER NOT NULL DEFAULT 1,
    default_value TEXT,                                  -- used when optional and not provided

    -- Validation (engine skips checks where the column is NULL)
    val_format VARCHAR(20),                              -- email | phone | url | date | uuid | ipv4
    val_min_length INTEGER,
    val_max_length INTEGER,
    val_min_value NUMERIC,                               -- for int/decimal
    val_max_value NUMERIC,
    val_pattern TEXT,                                    -- regex

    -- Sanitization (engine applies in this order before validation)
    san_trim_whitespace INTEGER NOT NULL DEFAULT 1,
    san_lowercase INTEGER NOT NULL DEFAULT 0,
    san_strip_html INTEGER NOT NULL DEFAULT 0,

    -- Recovery / LLM elicitation
    re_ask_if_missing INTEGER NOT NULL DEFAULT 0,
    re_ask_prompt TEXT,                                  -- verbatim string the LLM uses

    -- Field redaction (replaces masked_fields JSONB on the recipe row)
    is_masked INTEGER NOT NULL DEFAULT 0,                -- mask in execution_log + UI

    description TEXT NOT NULL,                           -- this IS the documentation

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.3',

    UNIQUE (recipe_id, var_name)
);

CREATE INDEX IF NOT EXISTS idx_cookbook_recipe_var_recipe_id  ON cookbook_recipe_var(recipe_id);
CREATE INDEX IF NOT EXISTS idx_cookbook_recipe_var_var_source ON cookbook_recipe_var(var_source);
CREATE INDEX IF NOT EXISTS idx_cookbook_recipe_var_is_masked  ON cookbook_recipe_var(is_masked);
CREATE INDEX IF NOT EXISTS idx_cookbook_recipe_var_is_deleted ON cookbook_recipe_var(is_deleted);


CREATE TABLE IF NOT EXISTS cookbook_recipe_var_allowed_value (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('CVA'),
    recipe_var_id VARCHAR(36) NOT NULL REFERENCES cookbook_recipe_var(id) ON DELETE CASCADE,

    allowed_value TEXT NOT NULL,                         -- the literal permitted value, e.g. "0"
    display_label VARCHAR(120),                          -- human-readable, e.g. "Normal"
    description TEXT,                                    -- short usage hint

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.3',

    UNIQUE (recipe_var_id, allowed_value)
);

CREATE INDEX IF NOT EXISTS idx_cookbook_recipe_var_allowed_value_recipe_var_id
    ON cookbook_recipe_var_allowed_value(recipe_var_id);


-- ============================================================================
-- BLOCK G: cookbook_recipe_output (per-output declaration; replaces JSONB)
-- ----------------------------------------------------------------------------
-- Replaces both cookbook_recipe.returns_schema JSONB AND the proposal's
-- output_map JSONB list. Each row declares one key the recipe's run()
-- return contract should populate, plus how to extract it from the raw
-- return and how to surface it back to the caller.
-- ============================================================================
CREATE TABLE IF NOT EXISTS cookbook_recipe_output (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('CRO'),
    recipe_id VARCHAR(36) NOT NULL,                      -- FK added below

    output_key VARCHAR(120) NOT NULL,                    -- key name in CookResponse.result, e.g. "lead_id"
    source_path TEXT NOT NULL,                           -- dot-path into raw return, e.g. "data.lead_id"
    value_type VARCHAR(20) NOT NULL DEFAULT 'string',    -- string | int | bool | decimal | date | array | object
    is_required INTEGER NOT NULL DEFAULT 0,              -- if 1, missing = MALFORMED_RESPONSE
    description TEXT,                                    -- what this value represents
    display_label VARCHAR(120),                          -- UI label for the render-card

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.3',

    UNIQUE (recipe_id, output_key)
);

CREATE INDEX IF NOT EXISTS idx_cookbook_recipe_output_recipe_id  ON cookbook_recipe_output(recipe_id);
CREATE INDEX IF NOT EXISTS idx_cookbook_recipe_output_is_deleted ON cookbook_recipe_output(is_deleted);


-- ============================================================================
-- BLOCK H: ALTER cookbook_recipe -- add hierarchy FKs + behavior flags;
--          MIGRATE JSONB data into row tables; DROP JSONB columns.
-- ----------------------------------------------------------------------------
-- 1. Add new scalar columns + FKs.
-- 2. (Operator step) Backfill the new tables from the dropped JSONB rows --
--    a Python helper does this; see _context/docs/root/COOKBOOK-EVOLUTION-PROPOSAL.md
--    "Live-DB backfill" section. The script reads existing arguments_schema /
--    returns_schema / metadata JSONB and emits INSERT statements for
--    cookbook_recipe_var / cookbook_recipe_output before this migration's
--    DROP COLUMN runs.
-- 3. Drop the old JSONB columns.
-- ============================================================================
ALTER TABLE cookbook_recipe
    ADD COLUMN IF NOT EXISTS system_id          VARCHAR(36) REFERENCES cookbook_system(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS module_id          VARCHAR(36) REFERENCES cookbook_module(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS auth_profile_id    VARCHAR(36) REFERENCES cookbook_auth_profile(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS template_id        VARCHAR(36) REFERENCES cookbook_template(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS is_read_only       INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS is_getset          INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS is_batch           INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS is_chainable       INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS is_render_card     INTEGER NOT NULL DEFAULT 1,  -- 2026-05-27 decision: auto-render-card default ON
    ADD COLUMN IF NOT EXISTS expected_duration_ms INTEGER,
    ADD COLUMN IF NOT EXISTS target_model       VARCHAR(120),  -- e.g. "crm.lead" for Odoo
    ADD COLUMN IF NOT EXISTS target_method      VARCHAR(120);  -- e.g. "create" for Odoo

-- Late-bind the recipe_var.recipe_id and recipe_output.recipe_id FKs now that
-- cookbook_recipe is in its final shape.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_cookbook_recipe_var_recipe_id'
    ) THEN
        ALTER TABLE cookbook_recipe_var
            ADD CONSTRAINT fk_cookbook_recipe_var_recipe_id
            FOREIGN KEY (recipe_id) REFERENCES cookbook_recipe(id) ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_cookbook_recipe_output_recipe_id'
    ) THEN
        ALTER TABLE cookbook_recipe_output
            ADD CONSTRAINT fk_cookbook_recipe_output_recipe_id
            FOREIGN KEY (recipe_id) REFERENCES cookbook_recipe(id) ON DELETE CASCADE;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_cookbook_recipe_system_id       ON cookbook_recipe(system_id);
CREATE INDEX IF NOT EXISTS idx_cookbook_recipe_module_id       ON cookbook_recipe(module_id);
CREATE INDEX IF NOT EXISTS idx_cookbook_recipe_auth_profile_id ON cookbook_recipe(auth_profile_id);
CREATE INDEX IF NOT EXISTS idx_cookbook_recipe_template_id     ON cookbook_recipe(template_id);
CREATE INDEX IF NOT EXISTS idx_cookbook_recipe_is_read_only    ON cookbook_recipe(is_read_only);
CREATE INDEX IF NOT EXISTS idx_cookbook_recipe_is_getset       ON cookbook_recipe(is_getset);

-- Drop the JSONB columns ONLY after backfill has happened. Operator must
-- run the backfill helper first; this migration assumes it's been done.
-- The DROPs are guarded so re-running is safe.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'cookbook_recipe' AND column_name = 'arguments_schema'
    ) THEN
        ALTER TABLE cookbook_recipe DROP COLUMN arguments_schema;
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'cookbook_recipe' AND column_name = 'returns_schema'
    ) THEN
        ALTER TABLE cookbook_recipe DROP COLUMN returns_schema;
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'cookbook_recipe' AND column_name = 'metadata'
    ) THEN
        ALTER TABLE cookbook_recipe DROP COLUMN metadata;
    END IF;
END $$;


-- ============================================================================
-- BLOCK I: ALTER kitchen_invocation -- normalize JSONB into row tables;
--          add envelope columns (user_message, recommended_action, cache_hit).
-- ----------------------------------------------------------------------------
-- Per-invocation child tables: kitchen_invocation_var (arguments + sanitized),
-- kitchen_invocation_output (mapped outputs), kitchen_invocation_validation_error.
-- ============================================================================
ALTER TABLE kitchen_invocation
    ADD COLUMN IF NOT EXISTS parent_invocation_id  VARCHAR(36) REFERENCES kitchen_invocation(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS user_message          TEXT,        -- customer-safe message from envelope
    ADD COLUMN IF NOT EXISTS recommended_action    TEXT,        -- optional next-step hint
    ADD COLUMN IF NOT EXISTS cache_hit             INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS raw_result_text       TEXT;        -- debug-only blob; NOT JSONB

CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_parent_invocation_id
    ON kitchen_invocation(parent_invocation_id);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_cache_hit
    ON kitchen_invocation(cache_hit);

-- Drop the old JSONB columns AFTER backfill helper has run.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'kitchen_invocation' AND column_name = 'arguments'
    ) THEN
        ALTER TABLE kitchen_invocation DROP COLUMN arguments;
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'kitchen_invocation' AND column_name = 'result'
    ) THEN
        ALTER TABLE kitchen_invocation DROP COLUMN result;
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'kitchen_invocation' AND column_name = 'metadata'
    ) THEN
        ALTER TABLE kitchen_invocation DROP COLUMN metadata;
    END IF;
END $$;


-- ============================================================================
-- BLOCK J: kitchen_invocation_var (per-arg row; replaces arguments JSONB)
-- ----------------------------------------------------------------------------
-- One row per variable the engine resolved for this invocation. Both
-- call_time and global_vars become rows here. raw_value is what came in;
-- sanitized_value is what the engine actually passed to run(). If is_masked
-- is set on the matching cookbook_recipe_var, raw_value + sanitized_value
-- are stored as the literal string '***MASKED***'.
-- ============================================================================
CREATE TABLE IF NOT EXISTS kitchen_invocation_var (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('KVR'),
    invocation_id VARCHAR(36) NOT NULL REFERENCES kitchen_invocation(id) ON DELETE CASCADE,
    recipe_var_id VARCHAR(36) REFERENCES cookbook_recipe_var(id) ON DELETE SET NULL,

    var_name VARCHAR(120) NOT NULL,                      -- duplicated so a deleted recipe_var row doesn't lose context
    var_source VARCHAR(20) NOT NULL,                     -- call_time | global_vars
    raw_value TEXT,                                      -- as received from caller / DB; NULL = absent
    sanitized_value TEXT,                                -- after trim/lowercase/strip_html; NULL = absent
    was_masked INTEGER NOT NULL DEFAULT 0,
    was_defaulted INTEGER NOT NULL DEFAULT 0,            -- 1 if the value came from default_value

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.3'
);

CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_var_invocation_id ON kitchen_invocation_var(invocation_id);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_var_recipe_var_id ON kitchen_invocation_var(recipe_var_id);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_var_var_name      ON kitchen_invocation_var(var_name);


-- ============================================================================
-- BLOCK K: kitchen_invocation_output (per-declared-output row; replaces result JSONB)
-- ----------------------------------------------------------------------------
-- One row per cookbook_recipe_output the engine extracted from the recipe's
-- run() return. Anything the recipe returned beyond the declared outputs
-- lands in kitchen_invocation.raw_result_text as a plain JSON string (for
-- debugging only, not indexed-into).
-- ============================================================================
CREATE TABLE IF NOT EXISTS kitchen_invocation_output (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('KVO'),
    invocation_id VARCHAR(36) NOT NULL REFERENCES kitchen_invocation(id) ON DELETE CASCADE,
    recipe_output_id VARCHAR(36) REFERENCES cookbook_recipe_output(id) ON DELETE SET NULL,

    output_key VARCHAR(120) NOT NULL,                    -- duplicated for survival of recipe_output delete
    value_text TEXT,                                     -- string-encoded value; NULL = absent in raw return
    value_type VARCHAR(20) NOT NULL DEFAULT 'string',    -- snapshot of recipe_output.value_type at extract time

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.3'
);

CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_output_invocation_id    ON kitchen_invocation_output(invocation_id);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_output_recipe_output_id ON kitchen_invocation_output(recipe_output_id);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_output_output_key       ON kitchen_invocation_output(output_key);


-- ============================================================================
-- BLOCK L: kitchen_invocation_validation_error (replaces validation_errors JSONB)
-- ============================================================================
CREATE TABLE IF NOT EXISTS kitchen_invocation_validation_error (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('KVE'),
    invocation_id VARCHAR(36) NOT NULL REFERENCES kitchen_invocation(id) ON DELETE CASCADE,
    recipe_var_id VARCHAR(36) REFERENCES cookbook_recipe_var(id) ON DELETE SET NULL,

    var_name VARCHAR(120) NOT NULL,                      -- which var failed
    error_class VARCHAR(50) NOT NULL,                    -- MissingRequired | FormatMismatch | RangeViolation | PatternMismatch | NotInAllowedValues
    error_message TEXT NOT NULL,                         -- short human-readable diagnostic

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.3'
);

CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_validation_error_invocation_id
    ON kitchen_invocation_validation_error(invocation_id);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_validation_error_var_name
    ON kitchen_invocation_validation_error(var_name);


-- ============================================================================
-- BLOCK M: ALTER kitchen_artifact -- drop metadata JSONB
-- ============================================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'kitchen_artifact' AND column_name = 'metadata'
    ) THEN
        ALTER TABLE kitchen_artifact DROP COLUMN metadata;
    END IF;
END $$;


-- ============================================================================
-- BLOCK M2: cookbook_event_trigger + cookbook_event_trigger_var
-- ----------------------------------------------------------------------------
-- DB-stored counterpart to file-based hyve-cookbook/recipes/*.py event-trigger
-- plugins. Cookbook sidecar will load these from DB instead of (or in
-- addition to) file-based plugins. Each row holds the python_body of an
-- async handler that subscribes to a firehose subtype, runs orchestration
-- in the sidecar process (NOT sandboxed -- it needs ctx.bridge / ctx.kitchen
-- access), and may call kitchen recipes + publish bridge commands.
--
-- Why a separate table from cookbook_recipe:
--   - Kitchen recipes run in subprocess sandbox; event triggers run in-process
--   - Kitchen recipes are request-response with args/returns/envelope;
--     event triggers are fire-and-forget with no return
--   - Kitchen recipes are reached via /v1/cook; event triggers fire on
--     firehose-event match
-- Forcing them into one table would mean half the columns are NULL for
-- half the rows.
-- ============================================================================
CREATE TABLE IF NOT EXISTS cookbook_event_trigger (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('CET'),
    system_id VARCHAR(36) REFERENCES cookbook_system(id) ON DELETE SET NULL,
    module_id VARCHAR(36) REFERENCES cookbook_module(id) ON DELETE SET NULL,

    trigger_name VARCHAR(120) NOT NULL UNIQUE,           -- snake_case, e.g. badge_to_user_arrived
    display_name VARCHAR(255),
    description TEXT NOT NULL,
    on_event VARCHAR(128) NOT NULL,                      -- firehose subtype, e.g. vision.badge.seen
    python_body TEXT NOT NULL,                           -- full async def handle(event, ctx) source
    entrypoint VARCHAR(120) NOT NULL DEFAULT 'handle',   -- callable name to invoke

    -- Behavior
    is_enabled INTEGER NOT NULL DEFAULT 1,
    -- kitchen_enabled gates whether the trigger can call ctx.kitchen.cook(...).
    -- Mirrors the gate already enforced for file-based recipes by Phase D item 7.
    kitchen_enabled INTEGER NOT NULL DEFAULT 1,

    -- Stats (updated on each fire by the sidecar)
    last_fired_date TIMESTAMP,
    fire_count BIGINT NOT NULL DEFAULT 0,
    error_count BIGINT NOT NULL DEFAULT 0,
    last_error_message TEXT,
    last_error_date TIMESTAMP,

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.3'
);

CREATE INDEX IF NOT EXISTS idx_cookbook_event_trigger_trigger_name    ON cookbook_event_trigger(trigger_name);
CREATE INDEX IF NOT EXISTS idx_cookbook_event_trigger_on_event        ON cookbook_event_trigger(on_event);
CREATE INDEX IF NOT EXISTS idx_cookbook_event_trigger_is_enabled      ON cookbook_event_trigger(is_enabled);
CREATE INDEX IF NOT EXISTS idx_cookbook_event_trigger_system_id       ON cookbook_event_trigger(system_id);
CREATE INDEX IF NOT EXISTS idx_cookbook_event_trigger_module_id       ON cookbook_event_trigger(module_id);
CREATE INDEX IF NOT EXISTS idx_cookbook_event_trigger_is_deleted      ON cookbook_event_trigger(is_deleted);


-- Per-event-payload-field metadata. Event triggers receive the full event
-- payload (event.payload dict) -- this table documents which fields the
-- handler reads so docs + GUI can show "this trigger consumes qr_payload,
-- face_hash, fields". Optional but useful for the docs UI.
CREATE TABLE IF NOT EXISTS cookbook_event_trigger_var (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('CTV'),
    event_trigger_id VARCHAR(36) NOT NULL REFERENCES cookbook_event_trigger(id) ON DELETE CASCADE,

    var_name VARCHAR(120) NOT NULL,                      -- payload field name, e.g. "qr_payload"
    var_type VARCHAR(20) NOT NULL DEFAULT 'string',
    is_required INTEGER NOT NULL DEFAULT 0,              -- if 1, trigger returns early when missing
    description TEXT NOT NULL,

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.3',

    UNIQUE (event_trigger_id, var_name)
);

CREATE INDEX IF NOT EXISTS idx_cookbook_event_trigger_var_event_trigger_id
    ON cookbook_event_trigger_var(event_trigger_id);


-- ============================================================================
-- BLOCK M3: cookbook_subscription_access (deny-all default; opt-IN access)
-- ----------------------------------------------------------------------------
-- Per-subscription access control. The decision (2026-05-27) is DENY-ALL:
-- a subscription has access to a system/module/recipe/event_trigger only
-- when at least one row in this table explicitly allows it.
--
-- Granularity: each row has subscription_id PLUS ONE of (system_id,
-- module_id, recipe_id, event_trigger_id). A system-level grant implies
-- access to every module / recipe / trigger under that system unless an
-- explicit deny row overrides it. The check order at runtime:
--    1. Look for a deny row at the most specific level (recipe / trigger).
--       If found, deny.
--    2. Look for an allow row at any level (system | module | recipe |
--       trigger). If found, allow.
--    3. Default: deny.
--
-- This generalises Phase D item 7's subscription_recipe_disabled (which
-- was a deny-only table at the recipe level under an allow-all default).
-- That table can either be migrated into this one or kept as a legacy
-- shim; for now we leave it in place and have the gate check BOTH tables.
-- ============================================================================
CREATE TABLE IF NOT EXISTS cookbook_subscription_access (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('CSA'),
    subscription_id VARCHAR(36) NOT NULL REFERENCES subscription(id) ON DELETE CASCADE,

    -- Exactly ONE of the following four must be non-NULL (enforced via CHECK).
    system_id        VARCHAR(36) REFERENCES cookbook_system(id) ON DELETE CASCADE,
    module_id        VARCHAR(36) REFERENCES cookbook_module(id) ON DELETE CASCADE,
    recipe_id        VARCHAR(36) REFERENCES cookbook_recipe(id) ON DELETE CASCADE,
    event_trigger_id VARCHAR(36) REFERENCES cookbook_event_trigger(id) ON DELETE CASCADE,

    access_action VARCHAR(10) NOT NULL DEFAULT 'allow',  -- 'allow' | 'deny'
    reason TEXT,                                         -- audit explanation for why this was granted/denied

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.3',

    CONSTRAINT cookbook_subscription_access_target_check CHECK (
        (CASE WHEN system_id        IS NOT NULL THEN 1 ELSE 0 END)
      + (CASE WHEN module_id        IS NOT NULL THEN 1 ELSE 0 END)
      + (CASE WHEN recipe_id        IS NOT NULL THEN 1 ELSE 0 END)
      + (CASE WHEN event_trigger_id IS NOT NULL THEN 1 ELSE 0 END) = 1
    ),
    CONSTRAINT cookbook_subscription_access_action_check
        CHECK (access_action IN ('allow', 'deny'))
);

CREATE INDEX IF NOT EXISTS idx_cookbook_subscription_access_subscription_id
    ON cookbook_subscription_access(subscription_id);
CREATE INDEX IF NOT EXISTS idx_cookbook_subscription_access_system_id
    ON cookbook_subscription_access(system_id) WHERE system_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cookbook_subscription_access_module_id
    ON cookbook_subscription_access(module_id) WHERE module_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cookbook_subscription_access_recipe_id
    ON cookbook_subscription_access(recipe_id) WHERE recipe_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cookbook_subscription_access_event_trigger_id
    ON cookbook_subscription_access(event_trigger_id) WHERE event_trigger_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cookbook_subscription_access_is_deleted
    ON cookbook_subscription_access(is_deleted);


-- ============================================================================
-- BLOCK M4: cookbook_system_config (engine behavior settings; key-value)
-- ----------------------------------------------------------------------------
-- Replaces the proposal's system_config table. Lookup table for engine-
-- wide behavior toggles (log retention, default timeout, max retries, etc.).
-- ============================================================================
CREATE TABLE IF NOT EXISTS cookbook_system_config (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('CSC'),

    config_key VARCHAR(120) NOT NULL UNIQUE,
    config_value TEXT NOT NULL,
    value_type VARCHAR(20) NOT NULL DEFAULT 'string',    -- string | int | bool | json_text
    description TEXT,
    -- min_edit_role gates GUI edits the same way cookbook_global_var does.
    min_edit_role VARCHAR(20) NOT NULL DEFAULT 'admin',

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.3',

    CONSTRAINT cookbook_system_config_min_edit_role_check
        CHECK (min_edit_role IN ('super_admin', 'admin', 'trainer', 'user', 'viewer'))
);

CREATE INDEX IF NOT EXISTS idx_cookbook_system_config_config_key   ON cookbook_system_config(config_key);
CREATE INDEX IF NOT EXISTS idx_cookbook_system_config_is_deleted   ON cookbook_system_config(is_deleted);

-- Seed engine defaults (idempotent on re-run).
INSERT INTO cookbook_system_config (config_key, config_value, value_type, description, min_edit_role, created_by)
VALUES
    ('log_retention_days',    '0',     'int',  '0 = keep forever; >0 = purge kitchen_invocation rows older than N days', 'super_admin', 'migration-003'),
    ('default_timeout_ms',    '10000', 'int',  'Default HTTP timeout in milliseconds for recipes that hit external APIs', 'admin',       'migration-003'),
    ('redis_enabled',         'true',  'bool', 'Whether the kitchen Redis result cache is active',                       'admin',       'migration-003'),
    ('max_retries',           '2',     'int',  'Retry attempts on transient SERVER_TIMEOUT errors',                      'admin',       'migration-003'),
    ('validation_strict_mode','true',  'bool', 'If true, any validation error blocks recipe execution',                  'admin',       'migration-003'),
    ('render_card_default',   'true',  'bool', 'Default for cookbook_recipe.is_render_card on new rows',                 'admin',       'migration-003')
ON CONFLICT (config_key) DO NOTHING;


-- ============================================================================
-- BLOCK M5: BLACKBOX-SIDE RENAME bridge_recipe -> bridge_event_subscription
-- ----------------------------------------------------------------------------
-- Resolves the word "recipe" overloading that arose when cookbook_recipe
-- (DB-stored kitchen-executable) and bridge_recipe (cookbook sidecar's
-- file-plugin metadata) ended up meaning different things. After this:
--   * cookbook_recipe         = a kitchen-executable callable (storage)
--   * cookbook_event_trigger  = a sidecar-process event handler (storage)
--   * bridge_event_subscription = the sidecar's runtime registration of
--                                 which trigger handles which firehose
--                                 event (formerly bridge_recipe)
--
-- This rename touches a table in 01-init-schema.sql owned by hyve-blackbox.
-- We're applying it here for atomicity with the cookbook evolution; a
-- companion edit to 01-init-schema.sql (in a separate change) updates
-- the canonical schema definition + bumps the blackbox schema_version
-- to v6.
-- ============================================================================
DO $$
BEGIN
    -- Rename table (converged-with-blackbox case: bridge_recipe exists from
    -- 01-init-schema.sql, we rename it to bridge_event_subscription).
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema = 'public' AND table_name = 'bridge_recipe')
       AND NOT EXISTS (SELECT 1 FROM information_schema.tables
                       WHERE table_schema = 'public' AND table_name = 'bridge_event_subscription') THEN
        ALTER TABLE bridge_recipe RENAME TO bridge_event_subscription;
    END IF;

    -- Rename columns
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'bridge_event_subscription' AND column_name = 'recipe_name') THEN
        ALTER TABLE bridge_event_subscription RENAME COLUMN recipe_name TO trigger_name;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'bridge_event_subscription' AND column_name = 'recipe_file_path') THEN
        ALTER TABLE bridge_event_subscription RENAME COLUMN recipe_file_path TO trigger_file_path;
    END IF;
END $$;

-- Rename indexes to match the new table+column names. Each statement is
-- IF EXISTS so it's a no-op when the source index isn't present (e.g.
-- standalone-mode kitchen DB where bridge_recipe never existed).
ALTER INDEX IF EXISTS idx_bridge_recipe_recipe_name RENAME TO idx_bridge_event_subscription_trigger_name;
ALTER INDEX IF EXISTS idx_bridge_recipe_on_event    RENAME TO idx_bridge_event_subscription_on_event;
ALTER INDEX IF EXISTS idx_bridge_recipe_is_enabled  RENAME TO idx_bridge_event_subscription_is_enabled;
ALTER INDEX IF EXISTS idx_bridge_recipe_is_deleted  RENAME TO idx_bridge_event_subscription_is_deleted;

-- STANDALONE FALLBACK: when running against a kitchen-only DB (no
-- blackbox schema), neither bridge_recipe NOR bridge_event_subscription
-- exists after the rename above. The cookbook sidecar still needs this
-- table to function -- it's the runtime registry of which event-trigger
-- handler subscribes to which firehose subtype. Create it from scratch
-- here. Schema must match the canonical definition in 01-init-schema.sql
-- (V6+).
CREATE TABLE IF NOT EXISTS bridge_event_subscription (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('BES'),

    trigger_name VARCHAR(128) NOT NULL UNIQUE,
    trigger_file_path TEXT,
    on_event VARCHAR(128) NOT NULL,
    description TEXT,

    is_enabled INTEGER NOT NULL DEFAULT 1,
    kitchen_enabled INTEGER NOT NULL DEFAULT 1,

    last_fired_date TIMESTAMP,
    fire_count BIGINT NOT NULL DEFAULT 0,
    error_count BIGINT NOT NULL DEFAULT 0,
    last_error_message TEXT,
    last_error_date TIMESTAMP,

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.0.6'
);

CREATE INDEX IF NOT EXISTS idx_bridge_event_subscription_trigger_name ON bridge_event_subscription(trigger_name);
CREATE INDEX IF NOT EXISTS idx_bridge_event_subscription_on_event     ON bridge_event_subscription(on_event);
CREATE INDEX IF NOT EXISTS idx_bridge_event_subscription_is_enabled   ON bridge_event_subscription(is_enabled);
CREATE INDEX IF NOT EXISTS idx_bridge_event_subscription_is_deleted   ON bridge_event_subscription(is_deleted);


-- ============================================================================
-- BLOCK N: TABLE + COLUMN COMMENTS (for psql \d+ + auto-doc generators)
-- ============================================================================
COMMENT ON TABLE cookbook_system IS
    'Top-level integration target (Odoo, GoogleMaps, Weather, ...). Recipes hang off cookbook_module which hangs off cookbook_system.';
COMMENT ON TABLE cookbook_module IS
    'Second-level grouping under a cookbook_system (CRM, Inventory, Calendar, ...). Each cookbook_recipe optionally belongs to one module.';
COMMENT ON TABLE cookbook_auth_profile IS
    'Named credential profile, e.g. odoo_test, odoo_prod. One profile = N cookbook_global_var rows. Recipes reference profile_id.';
COMMENT ON TABLE cookbook_global_var IS
    'Credential / config value resolved at recipe-execution time. is_secret = 1 means redact in logs + UI.';
COMMENT ON TABLE cookbook_template IS
    'DB-stored recipe template with Jinja2-style placeholders. Engine renders against (recipe + var rows + system + module) to produce cookbook_recipe.python_body. Re-renderable when the template changes.';
COMMENT ON TABLE cookbook_recipe IS
    'Storage of recipe definitions (the cookbook). Holds python_body, behavior flags, FKs into system/module/auth_profile/template. Execution lives in kitchen_invocation.';
COMMENT ON TABLE cookbook_recipe_var IS
    'One row per recipe variable. Replaces JSONB arguments_schema. Validation + sanitization + LLM re-ask prompts are first-class columns.';
COMMENT ON TABLE cookbook_recipe_var_allowed_value IS
    'Enumerated permitted values for a cookbook_recipe_var. Replaces JSONB val_allowed_values.';
COMMENT ON TABLE cookbook_recipe_output IS
    'One row per declared output key for a recipe. Replaces JSONB returns_schema + output_map. Used both for response shape validation and for auto-render-card field selection.';
COMMENT ON TABLE kitchen_invocation_var IS
    'Per-invocation snapshot of each variable the engine resolved. raw_value + sanitized_value as TEXT so secrets can be masked uniformly.';
COMMENT ON TABLE kitchen_invocation_output IS
    'Per-invocation snapshot of each declared output the engine extracted from the recipe return.';
COMMENT ON TABLE kitchen_invocation_validation_error IS
    'Per-invocation list of validation failures. Replaces JSONB validation_errors.';
COMMENT ON TABLE cookbook_event_trigger IS
    'DB-stored event-trigger plugins (counterpart to file-based hyve-cookbook/recipes/*.py). Runs IN the cookbook sidecar process, NOT sandboxed. Subscribes to a firehose subtype, orchestrates kitchen calls + bridge publishes.';
COMMENT ON TABLE cookbook_event_trigger_var IS
    'Per-payload-field documentation for cookbook_event_trigger. Optional but drives the docs UI + per-trigger required-field gates.';
COMMENT ON TABLE cookbook_subscription_access IS
    'Per-subscription access control for systems / modules / recipes / event_triggers. Deny-by-default: a subscription has access ONLY when a matching allow row exists. Deny rows at finer granularity override broader allow rows.';
COMMENT ON TABLE cookbook_system_config IS
    'Engine behavior settings as key-value rows. Replaces the sample proposal''s system_config. min_edit_role gates which user roles can modify each setting.';
COMMENT ON TABLE bridge_event_subscription IS
    'Runtime registry of which cookbook_event_trigger handles which firehose subtype, with per-subscription enable + fire counts. Renamed from bridge_recipe on 2026-05-27 so "recipe" unambiguously means cookbook_recipe.';


-- ============================================================================
-- BLOCK O: SCHEMA_VERSION INSERT
-- ============================================================================
-- Defensive: schema_version is defined in blackbox 01-init-schema.sql.
-- IF NOT EXISTS makes this migration runnable in isolation (e.g. via
-- direct psql without the blackbox schema having run yet).
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    description TEXT,
    applied_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO schema_version (version, description)
VALUES (
    103,
    'V103 (kitchen): Cookbook evolution. RENAMED kitchen_recipe* -> cookbook_recipe*; bridge_recipe -> bridge_event_subscription (with column renames recipe_name -> trigger_name, recipe_file_path -> trigger_file_path). ADDED cookbook_system, cookbook_module, cookbook_auth_profile, cookbook_global_var (with min_edit_role), cookbook_template, cookbook_recipe_var, cookbook_recipe_var_allowed_value, cookbook_recipe_output, cookbook_event_trigger, cookbook_event_trigger_var, cookbook_subscription_access (deny-all default), cookbook_system_config. ADDED kitchen_invocation_var, kitchen_invocation_output, kitchen_invocation_validation_error. DROPPED arguments_schema/returns_schema/metadata JSONB from cookbook_recipe, arguments/result/metadata JSONB from kitchen_invocation, metadata JSONB from kitchen_artifact. Added envelope cols (user_message, recommended_action, cache_hit, raw_result_text) on kitchen_invocation. Added behavior flag cols (is_read_only, is_getset, is_batch, is_chainable, is_render_card DEFAULT 1, expected_duration_ms, target_model, target_method) on cookbook_recipe.'
)
ON CONFLICT (version) DO NOTHING;


COMMIT;


-- ============================================================================
-- FOLLOW-UP (NOT in this migration -- separate change request)
-- ============================================================================
-- 1. Python patches:
--    - kitchen/sandbox/worker.py     -- inspect signature; support def run(vars: dict)
--    - kitchen/routes/cook.py        -- wrap recipe return as standard envelope
--    - kitchen/sandbox/sdk.py        -- new sdk.render.card(title, fields, status)
--    - kitchen/templates/renderer.py -- new module to render cookbook_template
--                                       against (recipe + var rows) into python_body
--    See _context/docs/root/COOKBOOK-EVOLUTION-PROPOSAL.md for the patch
--    outlines and acceptance criteria.
--
-- 2. Blackbox-side companion edit (DONE in this migration block M5, but
--    01-init-schema.sql still has the OLD bridge_recipe definition for
--    fresh-install paths; update it in a separate edit + bump blackbox
--    schema_version to v6.
--
-- 3. Backfill helper script:
--    hyve-blackbox/hyve-kitchen/migrations/003a_backfill_jsonb_into_rows.py
--    Reads pre-migration arguments_schema / returns_schema / arguments
--    JSONB rows and emits INSERTs into cookbook_recipe_var / cookbook_recipe_output /
--    kitchen_invocation_var / kitchen_invocation_output. MUST run before
--    the DROP COLUMN blocks above on a populated DB.
-- ============================================================================
