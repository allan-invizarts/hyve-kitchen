-- ============================================================================
-- HYVE KITCHEN - POSTGRESQL 16 SCHEMA
-- ============================================================================
-- Adds the kitchen_* tables to the existing hyve_llm database.
-- Follows hyve-blackbox conventions (see devops/postgres/01-init-schema.sql):
--   - Primary Key: id VARCHAR(36) DEFAULT generate_custom_guid('KTN')
--   - Required columns: sort_order, is_deleted, created_by, created_date,
--                       changed_by, changed_date, changed_during_version
--   - Boolean fields: is_ prefix
--   - Timestamps: UTC, _date suffix
--   - Foreign Keys: related_table_id pattern
--   - Indexes: idx_table_name_column_name
--   - Queries: WHERE 1=1 AND is_deleted=0
--
-- Apply with:
--   docker exec -i hyve-postgres psql -U hyve_admin hyve_llm \
--     < migrations/001_kitchen_schema.sql
-- ============================================================================

-- ============================================================================
-- BLOCK 0: STANDALONE BOOTSTRAP (2026-05-27)
-- ============================================================================
-- Lets the kitchen schema be applied against a totally fresh database
-- with NO blackbox schema present. Useful for isolated testing.
--
-- Each item below is defensive: if it already exists (because the
-- blackbox 01-init-schema.sql has been applied alongside this DB), the
-- bootstrap is a no-op. If it's missing, the bootstrap creates a
-- minimum-viable version.
--
-- Three prerequisites the kitchen depends on:
--   1. generate_custom_guid() function -- used as the DEFAULT on every
--      kitchen table's PK. Canonical body lives in 01-init-schema.sql;
--      copied verbatim here for standalone use.
--   2. schema_version table -- migration tracking. Already created by
--      002/003/004 defensively; included here so version 101 lands cleanly
--      when 001 is the first kitchen file run.
--   3. subscription table -- V103's cookbook_subscription_access FKs into
--      it. The standalone version is a STRICT SUBSET of the blackbox
--      schema's subscription table (no user_id FK, no status CHECK
--      constraint, fewer columns). Sufficient for kitchen's needs;
--      converge with blackbox by dropping + re-applying 01-init-schema.sql.
--
-- CONVERGENCE NOTE: if you later want to add the full blackbox schema
-- to a DB that was bootstrapped here, you'll hit "relation subscription
-- already exists" because the stub uses CREATE TABLE not CREATE TABLE
-- IF NOT EXISTS in 01-init-schema.sql. To converge:
--     DROP TABLE subscription CASCADE;  -- this cascades to cookbook_subscription_access
--     -- apply 01-init-schema.sql + 02-04 blackbox seeds
--     -- re-apply 003 + 004 + 002_cookbook_evolution_seed.sql

-- 0.1 -- generate_custom_guid()
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'generate_custom_guid') THEN
        EXECUTE $func$
        CREATE OR REPLACE FUNCTION generate_custom_guid(identifier_code TEXT DEFAULT 'VVV')
        RETURNS VARCHAR(36) AS $body$
        DECLARE
            year_month_day TEXT;
            hour_minute TEXT;
            second_ms TEXT;
            ms_identifier TEXT;
            random_part TEXT;
            result VARCHAR(36);
        BEGIN
            year_month_day := TO_CHAR(NOW() AT TIME ZONE 'UTC', 'YYYYMMDD');
            hour_minute := TO_CHAR(NOW() AT TIME ZONE 'UTC', 'HH24MI');
            second_ms := TO_CHAR(NOW() AT TIME ZONE 'UTC', 'SSMS');
            ms_identifier := SUBSTRING(TO_CHAR(NOW() AT TIME ZONE 'UTC', 'MS'), 2, 1) ||
                             UPPER(identifier_code);
            random_part := UPPER(SUBSTRING(MD5(RANDOM()::TEXT || CLOCK_TIMESTAMP()::TEXT), 1, 12));
            result := year_month_day || '-' ||
                      hour_minute || '-' ||
                      SUBSTRING(second_ms, 1, 4) || '-' ||
                      ms_identifier || '-' ||
                      random_part;
            RETURN result;
        END;
        $body$ LANGUAGE plpgsql;
        $func$;
    END IF;
END $$;

-- 0.2 -- schema_version table
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    description TEXT,
    applied_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 0.3 -- minimal subscription table (V103 cookbook_subscription_access FKs into this)
-- WARNING: if blackbox 01-init-schema.sql is later applied to the same DB,
-- its CREATE TABLE subscription (no IF NOT EXISTS) will collide with this
-- stub. See the CONVERGENCE NOTE at the top of Block 0.
CREATE TABLE IF NOT EXISTS subscription (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('SUB'),
    subscription_name VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'ACTIVE',
    metadata JSONB DEFAULT '{}'::JSONB,
    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.0.1'
);
CREATE INDEX IF NOT EXISTS idx_subscription_subscription_name ON subscription(subscription_name);
CREATE INDEX IF NOT EXISTS idx_subscription_is_deleted        ON subscription(is_deleted);

-- 0.4 -- seed a test subscription so the standalone kitchen has something
-- to grant access to right out of the gate. Idempotent.
INSERT INTO subscription (id, subscription_name, status, created_by)
VALUES ('KITCHEN-STANDALONE-TEST', 'kitchen-standalone-test', 'ACTIVE', 'standalone-bootstrap')
ON CONFLICT (id) DO NOTHING;


-- pgvector for future semantic search of recipes
CREATE EXTENSION IF NOT EXISTS "vector";


-- ============================================================================
-- KITCHEN_RECIPE — the live, current definition of a callable function
-- ============================================================================
-- One row per logical recipe. The body + JSONSchema in this table are the
-- "current" version pointed at by current_version_id; full history lives in
-- kitchen_recipe_version.
CREATE TABLE IF NOT EXISTS kitchen_recipe (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('KTN'),

    -- Identity
    name VARCHAR(120) UNIQUE NOT NULL,           -- snake_case, e.g. warehouse_low_stock
    display_name VARCHAR(255),                   -- "Find Low-Stock Warehouse Items"
    description TEXT NOT NULL,                   -- shown to the LLM in tool manifest

    -- Pointer to the live version in kitchen_recipe_version
    current_version_id VARCHAR(36),

    -- Convenience snapshot of the current version (denormalized for read perf).
    -- Updated atomically with current_version_id.
    arguments_schema JSONB NOT NULL DEFAULT '{}'::JSONB,  -- JSONSchema for arguments
    returns_schema   JSONB,                                -- JSONSchema describing result shape
    python_body      TEXT NOT NULL,                        -- full Python source
    entrypoint       VARCHAR(120) NOT NULL DEFAULT 'run',  -- function name to invoke

    -- Behavior
    is_streaming     INTEGER NOT NULL DEFAULT 0,           -- reserved for future
    timeout_seconds  INTEGER NOT NULL DEFAULT 30,
    memory_mb        INTEGER NOT NULL DEFAULT 512,

    -- Visibility
    is_enabled       INTEGER NOT NULL DEFAULT 1,           -- gateway will only advertise enabled tools
    is_internal      INTEGER NOT NULL DEFAULT 0,           -- internal-only (not advertised to LLM)
    required_role    VARCHAR(50),                          -- e.g. 'admin'; NULL = anyone

    -- Semantic search (filled by gateway when present)
    description_embedding vector(768),

    -- Metadata
    metadata JSONB DEFAULT '{}'::JSONB,

    -- Standard Hyve audit columns
    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.0'
);

CREATE INDEX IF NOT EXISTS idx_kitchen_recipe_name        ON kitchen_recipe(name);
CREATE INDEX IF NOT EXISTS idx_kitchen_recipe_is_enabled  ON kitchen_recipe(is_enabled);
CREATE INDEX IF NOT EXISTS idx_kitchen_recipe_is_deleted  ON kitchen_recipe(is_deleted);
CREATE INDEX IF NOT EXISTS idx_kitchen_recipe_required_role ON kitchen_recipe(required_role);
-- HNSW index for cosine similarity on the description embedding (when used)
CREATE INDEX IF NOT EXISTS idx_kitchen_recipe_embedding
    ON kitchen_recipe USING hnsw (description_embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);


-- ============================================================================
-- KITCHEN_RECIPE_VERSION — append-only history of recipe edits
-- ============================================================================
CREATE TABLE IF NOT EXISTS kitchen_recipe_version (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('KTV'),
    recipe_id VARCHAR(36) NOT NULL REFERENCES kitchen_recipe(id) ON DELETE CASCADE,

    version_number INTEGER NOT NULL,             -- 1, 2, 3, ...
    arguments_schema JSONB NOT NULL,
    returns_schema   JSONB,
    python_body      TEXT NOT NULL,
    entrypoint       VARCHAR(120) NOT NULL DEFAULT 'run',
    change_note      TEXT,

    -- Standard Hyve audit columns (no soft delete on a history row)
    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.0',

    UNIQUE (recipe_id, version_number)
);

CREATE INDEX IF NOT EXISTS idx_kitchen_recipe_version_recipe_id ON kitchen_recipe_version(recipe_id);

-- Late-bind the FK on current_version_id now that kitchen_recipe_version exists.
ALTER TABLE kitchen_recipe
    ADD CONSTRAINT fk_kitchen_recipe_current_version
    FOREIGN KEY (current_version_id) REFERENCES kitchen_recipe_version(id) ON DELETE SET NULL;


-- ============================================================================
-- KITCHEN_RECIPE_TAG — many-to-many tagging (warehouse, crm, calendar, ...)
-- ============================================================================
CREATE TABLE IF NOT EXISTS kitchen_recipe_tag (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('KTT'),
    recipe_id VARCHAR(36) NOT NULL REFERENCES kitchen_recipe(id) ON DELETE CASCADE,
    tag VARCHAR(80) NOT NULL,

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.0',

    UNIQUE (recipe_id, tag)
);

CREATE INDEX IF NOT EXISTS idx_kitchen_recipe_tag_tag ON kitchen_recipe_tag(tag);


-- ============================================================================
-- KITCHEN_INVOCATION — one row per execution
-- ============================================================================
CREATE TABLE IF NOT EXISTS kitchen_invocation (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('KTI'),
    recipe_id VARCHAR(36) NOT NULL REFERENCES kitchen_recipe(id) ON DELETE RESTRICT,
    recipe_version_id VARCHAR(36) REFERENCES kitchen_recipe_version(id) ON DELETE SET NULL,
    recipe_name VARCHAR(120) NOT NULL,           -- duplicated for fast log lookup

    -- Caller context
    session_id VARCHAR(36),                      -- hyve session if known
    character_id VARCHAR(36),                    -- character that invoked, if any
    user_id VARCHAR(36),                         -- authenticated user, if any
    caller VARCHAR(50) NOT NULL DEFAULT 'gateway',  -- gateway | admin | direct

    -- Payload
    arguments JSONB NOT NULL DEFAULT '{}'::JSONB,
    result JSONB,
    error_message TEXT,
    error_class VARCHAR(120),

    -- Status: success | failure | timeout | sandbox_error | invalid_args | missing_args
    status VARCHAR(20) NOT NULL,

    -- Timing
    started_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_date TIMESTAMP,
    duration_ms INTEGER,

    -- Sandbox stats
    sandbox_cpu_ms INTEGER,
    sandbox_peak_memory_kb INTEGER,
    sandbox_stdout_bytes INTEGER,
    sandbox_stderr_bytes INTEGER,

    -- Metadata
    metadata JSONB DEFAULT '{}'::JSONB,

    -- Standard Hyve audit columns
    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.0'
);

CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_recipe_id    ON kitchen_invocation(recipe_id);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_recipe_name  ON kitchen_invocation(recipe_name);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_session_id   ON kitchen_invocation(session_id);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_status       ON kitchen_invocation(status);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_started_date ON kitchen_invocation(started_date);


-- ============================================================================
-- KITCHEN_ARTIFACT — images/files produced during an invocation
-- ============================================================================
CREATE TABLE IF NOT EXISTS kitchen_artifact (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('KTA'),
    invocation_id VARCHAR(36) NOT NULL REFERENCES kitchen_invocation(id) ON DELETE CASCADE,

    filename VARCHAR(255) NOT NULL,              -- {id}.png etc.
    content_type VARCHAR(80) NOT NULL DEFAULT 'image/png',
    size_bytes BIGINT NOT NULL,
    sha256 VARCHAR(64),

    public_url TEXT NOT NULL,                    -- absolute, e.g. https://kitchen.../artifacts/{id}.png
    storage_path TEXT NOT NULL,                  -- on-disk path on the kitchen container

    expires_date TIMESTAMP,                      -- NULL = no expiry (pruner ignores)
    is_pruned INTEGER NOT NULL DEFAULT 0,

    metadata JSONB DEFAULT '{}'::JSONB,

    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.1.0'
);

CREATE INDEX IF NOT EXISTS idx_kitchen_artifact_invocation_id ON kitchen_artifact(invocation_id);
CREATE INDEX IF NOT EXISTS idx_kitchen_artifact_expires_date  ON kitchen_artifact(expires_date);


-- ============================================================================
-- Helpful view: each recipe's latest invocation
-- ============================================================================
CREATE OR REPLACE VIEW kitchen_recipe_latest_invocation AS
SELECT DISTINCT ON (r.id)
    r.id           AS recipe_id,
    r.name         AS recipe_name,
    i.id           AS invocation_id,
    i.status       AS last_status,
    i.duration_ms  AS last_duration_ms,
    i.started_date AS last_started_date
FROM kitchen_recipe r
LEFT JOIN kitchen_invocation i ON i.recipe_id = r.id AND i.is_deleted = 0
WHERE r.is_deleted = 0
ORDER BY r.id, i.started_date DESC NULLS LAST;


-- ============================================================================
-- Schema version (V101 -- kitchen baseline)
-- ============================================================================
-- Defensive: schema_version is canonically defined in blackbox
-- 01-init-schema.sql, but this migration may run standalone (e.g. when
-- bringing up kitchen against a fresh DB that hasn't had the blackbox
-- schema applied yet, or via direct psql instead of devops/scripts/migrate.py).
-- The IF NOT EXISTS keeps this migration self-sufficient.
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    description TEXT,
    applied_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO schema_version (version, description)
VALUES (101,
        'Kitchen V101: baseline kitchen_recipe + kitchen_recipe_version + kitchen_recipe_tag + kitchen_invocation + kitchen_artifact tables. The 100-series keeps kitchen schema versions distinct from the blackbox versions (1-99).')
ON CONFLICT (version) DO NOTHING;
