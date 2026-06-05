-- Shared Odoo cookbook scaffolding for Tier 4 analytics recipes.
-- Apply before any analyze_*_insert.sql in this directory.

BEGIN;

INSERT INTO cookbook_system (
    system_label, display_name, description, homepage_url, icon_filename, sort_order, created_by
)
VALUES (
    'odoo', 'Odoo ERP', 'Odoo ERP instance', 'http://localhost:8069', 'odoo.svg', 10, 'tier4-generator'
)
ON CONFLICT (system_label) DO NOTHING;

INSERT INTO cookbook_module (
    system_id, module_label, display_name, description, sort_order, created_by
)
SELECT id, 'analytics', 'Analytics', 'Tier 4 cross-functional CDM analyzers', 30, 'tier4-generator'
FROM cookbook_system WHERE system_label = 'odoo'
ON CONFLICT (system_id, module_label) DO NOTHING;

INSERT INTO cookbook_auth_profile (
    system_id, profile_label, display_name, description, is_active, sort_order, created_by
)
SELECT id, 'odoo_test', 'Odoo - Test Instance', 'Local Odoo for development.', 1, 10, 'tier4-generator'
FROM cookbook_system WHERE system_label = 'odoo'
ON CONFLICT (system_id, profile_label) DO NOTHING;

COMMIT;
