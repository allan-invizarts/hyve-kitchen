-- V105 Phase 2 metadata for Tier 4 recipes (apply AFTER hyve-blackbox PR-1 migration)
-- Updates cookbook_recipe rows seeded by *_insert.sql files in this directory.
-- Safe to re-run when columns exist.

BEGIN;

UPDATE cookbook_recipe SET
    tier = 'tier4',
    cache_scope = 'tenant',
    is_read_only = 1,
    is_chainable = 1
WHERE name IN (
    'analyze_spend_trend',
    'analyze_inventory_gaps',
    'analyze_churn_signals',
    'analyze_customer_ltv',
    'analyze_customer_segment',
    'analyze_store_session_metrics'
);

UPDATE cookbook_recipe SET cdm_output_type = 'SpendTrend', cdm_input_types_csv = 'CommonTransaction', cache_ttl_seconds = 120
WHERE name = 'analyze_spend_trend';

UPDATE cookbook_recipe SET cdm_output_type = 'GapReport', cdm_input_types_csv = 'CommonInventorySnapshot,CommonTransaction', cache_ttl_seconds = 120
WHERE name = 'analyze_inventory_gaps';

UPDATE cookbook_recipe SET cdm_output_type = 'ChurnScore', cdm_input_types_csv = 'CommonCustomerProfile,CommonTransaction,CommonServiceTicket', cache_ttl_seconds = 120
WHERE name = 'analyze_churn_signals';

UPDATE cookbook_recipe SET cdm_output_type = 'LTVProjection', cdm_input_types_csv = 'CommonTransaction,CommonLoyaltyStatus', cache_ttl_seconds = 120
WHERE name = 'analyze_customer_ltv';

UPDATE cookbook_recipe SET cdm_output_type = 'SegmentProfile', cdm_input_types_csv = 'CommonTransaction', cache_ttl_seconds = 120
WHERE name = 'analyze_customer_segment';

UPDATE cookbook_recipe SET cdm_output_type = 'SessionMetrics', cdm_input_types_csv = 'CommonKioskSession', cache_ttl_seconds = 120
WHERE name = 'analyze_store_session_metrics';

COMMIT;
