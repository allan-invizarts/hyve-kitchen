-- ============================================================================
-- HYVE KITCHEN - ASYNC JOBS + RESULT CACHE (002)
-- ============================================================================
-- Adds:
--   1. kitchen_recipe.cache_ttl_seconds   -- Redis result-cache TTL hint
--   2. kitchen_recipe.is_async_capable    -- recipe declares it can run async
--   3. kitchen_invocation.is_async        -- this invocation was started async
--   4. kitchen_invocation_job             -- new table tracking async state
--                                         -- (callback URL, callback delivery,
--                                         --  bridge correlation, retry state)
--
-- Async flow:
--   1. POST /v1/cook/async {name, arguments, callback_url} -> {job_id, status:"queued"}
--   2. kitchen worker picks up the job, runs the recipe in the existing
--      subprocess executor.
--   3. On completion kitchen POSTs to callback_url with the same CookResponse
--      shape used by sync /v1/cook.
--   4. Job row tracks delivery attempts; on permanent failure the result
--      stays in kitchen_invocation_job.result_payload so admin can replay.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Extend kitchen_recipe
-- ----------------------------------------------------------------------------
ALTER TABLE kitchen_recipe
    ADD COLUMN IF NOT EXISTS cache_ttl_seconds INTEGER DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS is_async_capable INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN kitchen_recipe.cache_ttl_seconds IS
    'When set, /v1/cook results for this recipe are cached in Redis under key kitchen:recipe:{name}:result:{args_hash} for this many seconds. NULL = no caching.';

COMMENT ON COLUMN kitchen_recipe.is_async_capable IS
    '1 = recipe is safe to invoke through /v1/cook/async (idempotent OR uses kitchen_invocation_job.idempotency_key for dedup). 0 = sync only.';


-- ----------------------------------------------------------------------------
-- Extend kitchen_invocation
-- ----------------------------------------------------------------------------
ALTER TABLE kitchen_invocation
    ADD COLUMN IF NOT EXISTS is_async INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS job_id VARCHAR(36) DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS subscription_id VARCHAR(36) DEFAULT NULL;

CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_is_async ON kitchen_invocation(is_async);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_job_id ON kitchen_invocation(job_id);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_subscription_id ON kitchen_invocation(subscription_id);


-- ----------------------------------------------------------------------------
-- KITCHEN_INVOCATION_JOB - async lifecycle
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS kitchen_invocation_job (
    id VARCHAR(36) NOT NULL PRIMARY KEY DEFAULT generate_custom_guid('JOB'),
    invocation_id VARCHAR(36) REFERENCES kitchen_invocation(id) ON DELETE CASCADE,

    -- Request envelope (kept on the job row so an async caller can be
    -- looked up without joining through kitchen_invocation).
    recipe_name VARCHAR(128) NOT NULL,
    arguments JSONB NOT NULL DEFAULT '{}'::JSONB,
    caller VARCHAR(64) NOT NULL DEFAULT 'unknown',
    session_id VARCHAR(36),
    character_id VARCHAR(36),
    subscription_id VARCHAR(36),
    user_id VARCHAR(36),

    -- Idempotency: when set, repeat enqueues with the same key collapse onto
    -- the same job (in-progress or terminal). Bridge can derive this from
    -- (session_id, recipe_name, args_hash) to avoid double-fires.
    idempotency_key VARCHAR(128),

    -- Async delivery
    callback_url TEXT,                           -- bridge URL to POST result
    callback_method VARCHAR(8) NOT NULL DEFAULT 'POST',
    callback_headers JSONB DEFAULT '{}'::JSONB,  -- e.g. {"Authorization":"Bearer ..."}

    -- State
    status VARCHAR(16) NOT NULL DEFAULT 'queued',
    -- queued -> running -> success | failure | timeout | cancelled
    queued_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_date TIMESTAMP,
    completed_date TIMESTAMP,
    duration_ms INTEGER,

    -- Result snapshot (in case the callback fails and admin needs to replay)
    result_payload JSONB,                        -- the full CookResponse body

    -- Callback delivery tracking
    callback_attempts INTEGER NOT NULL DEFAULT 0,
    callback_last_attempt_date TIMESTAMP,
    callback_last_status_code INTEGER,
    callback_last_error TEXT,
    callback_delivered_date TIMESTAMP,           -- NULL until a 2xx arrives

    -- Standard Columns
    sort_order INTEGER NOT NULL DEFAULT 999,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    created_by VARCHAR(50) NOT NULL DEFAULT '',
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by VARCHAR(50) NOT NULL DEFAULT '',
    changed_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_during_version VARCHAR(15) NOT NULL DEFAULT '0.0.2',

    CONSTRAINT kitchen_invocation_job_status_check CHECK (
        status IN ('queued','running','success','failure','timeout','cancelled')
    )
);

CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_job_status ON kitchen_invocation_job(status);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_job_recipe_name ON kitchen_invocation_job(recipe_name);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_job_session_id ON kitchen_invocation_job(session_id);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_job_subscription_id ON kitchen_invocation_job(subscription_id);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_job_idempotency_key ON kitchen_invocation_job(idempotency_key)
    WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_job_callback_delivered_date ON kitchen_invocation_job(callback_delivered_date)
    WHERE callback_delivered_date IS NULL;
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_job_queued_date ON kitchen_invocation_job(queued_date);
CREATE INDEX IF NOT EXISTS idx_kitchen_invocation_job_is_deleted ON kitchen_invocation_job(is_deleted);

COMMENT ON TABLE kitchen_invocation_job IS
    'Async invocation tracking. Created by POST /v1/cook/async; updated as the worker progresses; callback_delivered_date set when bridge has acked the result.';


-- ----------------------------------------------------------------------------
-- Schema version
-- ----------------------------------------------------------------------------
-- Defensive: the canonical schema_version table is defined in the
-- blackbox 01-init-schema.sql, but this migration may run in isolation
-- (e.g. when bringing up kitchen against a DB that hasn't had the
-- blackbox schema applied yet, or when the operator runs migrations
-- manually via psql instead of through devops/scripts/migrate.py).
-- The IF NOT EXISTS makes the migration self-sufficient.
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    description TEXT,
    applied_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO schema_version (version, description)
VALUES (102,
        'Kitchen V102: async job tracking (kitchen_invocation_job) + cache_ttl_seconds on kitchen_recipe + is_async on kitchen_invocation. Uses 100-series version numbers so kitchen migrations stay distinct from blackbox.')
ON CONFLICT (version) DO NOTHING;
