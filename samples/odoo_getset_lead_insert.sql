-- Sample insert for cookbook Get/Set lead recipe (idempotent)
-- Run this against your hyve_llm DB after migrations are applied.

BEGIN;

-- system
INSERT INTO cookbook_system (
    system_label, display_name, description, homepage_url, icon_filename, sort_order, created_by
)
VALUES (
    'odoo', 'Odoo ERP', 'Odoo ERP instance', 'http://localhost:8069', 'odoo.svg', 10, 'recipe-generator'
)
ON CONFLICT (system_label) DO NOTHING;

-- module
INSERT INTO cookbook_module (
    system_id, module_label, display_name, description, sort_order, created_by
)
SELECT id, 'crm', 'Customer Relationship Management', 'CRM module', 10, 'recipe-generator'
FROM cookbook_system WHERE system_label = 'odoo'
ON CONFLICT (system_id, module_label) DO NOTHING;

-- auth profile
INSERT INTO cookbook_auth_profile (
    system_id, profile_label, display_name, description, is_active, sort_order, created_by
)
SELECT id, 'odoo_test', 'Odoo - Test Instance', 'Local docker-compose Odoo for development.', 1, 10, 'recipe-generator'
FROM cookbook_system WHERE system_label = 'odoo'
ON CONFLICT (system_id, profile_label) DO NOTHING;

-- template row (optional placeholder) - use actual column names present in migrations
INSERT INTO cookbook_template (
    template_label, display_name, description, template_text, created_by
)
VALUES (
    'odoo_getset_lead', 'Odoo Get/Set Lead', 'Placeholder template: renders to python_body', '-- placeholder: recipe renders into python_body from templates/odoo_getset_lead.py --', 'recipe-generator'
)
ON CONFLICT (template_label) DO NOTHING;

-- recipe (assumes cookbook_system/module/auth_profile exist)
INSERT INTO cookbook_recipe (
    id, name, display_name, description, system_id, module_id, auth_profile_id, python_body, is_enabled, created_by
)
SELECT
    generate_custom_guid('KTN'), 'odoo_getset_lead', 'Odoo Get/Set Lead', 'Find or create CRM lead by face hash/email/phone',
    s.id, m.id, p.id, t.template_text, 1, 'recipe-generator'
FROM cookbook_system s
JOIN cookbook_module m ON m.system_id = s.id AND m.module_label = 'crm'
JOIN cookbook_auth_profile p ON p.system_id = s.id AND p.profile_label = 'odoo_test'
JOIN cookbook_template t ON t.template_label = 'odoo_getset_lead'
WHERE s.system_label = 'odoo'
ON CONFLICT (name) DO NOTHING;

-- vars (call-time inputs expected from LLM caller)
INSERT INTO cookbook_recipe_var (
    recipe_id, var_name, var_type, is_required, description, sort_order, created_by
)
SELECT r.id, v.var_name, v.var_type, v.is_required, v.description, v.sort_order, 'recipe-generator'
FROM cookbook_recipe r
CROSS JOIN (VALUES
    ('lead_name', 'string', 0, 'Lead display name', 10),
    ('lead_email', 'string', 0, 'Lead email address', 20),
    ('lead_phone', 'string', 0, 'Lead phone number', 30),
    ('face_hash', 'string', 0, 'Hyve face hash', 40)
) AS v(var_name, var_type, is_required, description, sort_order)
WHERE r.name = 'odoo_getset_lead'
ON CONFLICT (recipe_id, var_name) DO NOTHING;

-- outputs
INSERT INTO cookbook_recipe_output (
    recipe_id, output_key, source_path, value_type, is_required, description, display_label, sort_order, created_by
)
SELECT r.id, 'lead_id', 'data.lead_id', 'string', 0, 'Primary created/found lead id', 'Lead ID', 10, 'recipe-generator'
FROM cookbook_recipe r
WHERE r.name = 'odoo_getset_lead'
ON CONFLICT (recipe_id, output_key) DO NOTHING;

COMMIT;
