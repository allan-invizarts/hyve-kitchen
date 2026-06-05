-- Sample insert for Tier 3.5 normalize_customer_profile recipe
-- Run this against your hyve_llm DB after migrations are applied.

BEGIN;

-- system / module / auth profile
INSERT INTO cookbook_system (
    system_label, display_name, description, homepage_url, icon_filename, sort_order, created_by
)
VALUES (
    'odoo', 'Odoo ERP', 'Odoo ERP instance', 'http://localhost:8069', 'odoo.svg', 10, 'recipe-generator'
)
ON CONFLICT (system_label) DO NOTHING;

INSERT INTO cookbook_module (
    system_id, module_label, display_name, description, sort_order, created_by
)
SELECT id, 'crm', 'Customer Relationship Management', 'CRM module', 10, 'recipe-generator'
FROM cookbook_system WHERE system_label = 'odoo'
ON CONFLICT (system_id, module_label) DO NOTHING;

INSERT INTO cookbook_auth_profile (
    system_id, profile_label, display_name, description, is_active, sort_order, created_by
)
SELECT id, 'odoo_test', 'Odoo - Test Instance', 'Local docker-compose Odoo for development.', 1, 10, 'recipe-generator'
FROM cookbook_system WHERE system_label = 'odoo'
ON CONFLICT (system_id, profile_label) DO NOTHING;

WITH new_recipe AS (
    INSERT INTO cookbook_recipe (
        name, display_name, description,
        system_id, module_id, auth_profile_id, template_id,
        python_body, entrypoint,
        timeout_seconds, memory_mb,
        is_enabled, is_internal, required_role,
        is_read_only, is_getset, is_batch, is_chainable, is_render_card,
        expected_duration_ms, created_by
    )
    SELECT
        'normalize_customer_profile',
        'Normalize Customer Profile',
        'Normalize Odoo CRM lead payloads into the common customer profile format for Tier 3.5 processing.',
        (SELECT id FROM cookbook_system WHERE system_label = 'odoo'),
        (SELECT id FROM cookbook_module
           WHERE module_label = 'crm'
             AND system_id = (SELECT id FROM cookbook_system WHERE system_label = 'odoo')),
        (SELECT id FROM cookbook_auth_profile WHERE profile_label = 'odoo_test'),
        NULL,
        $PY$
"""Normalize Odoo CRM lead payloads into the common customer profile format.

This Tier 3.5 normalizer converts raw Odoo lead data into a normalized
customer profile contract that Hyve Kitchen can consume for analytics,
segmentation, and downstream enrichment.
"""

import json


def _parse_lead_input(lead_json):
    if isinstance(lead_json, str):
        lead = json.loads(lead_json)
    else:
        lead = lead_json
    if not isinstance(lead, dict):
        raise ValueError('Expected lead payload to be a JSON object')
    return lead


def _normalize_customer_profile(raw_lead):
    lead = _parse_lead_input(raw_lead)

    return {
        'customer_id': f"odoo:lead:{lead.get('id')}",
        'source_system': 'odoo',
        'source_id': str(lead.get('id', '')) if lead.get('id') is not None else None,
        'name': lead.get('name'),
        'email': lead.get('email_from') or lead.get('email'),
        'phone': lead.get('phone'),
        'face_hash': lead.get('x_hyve_face_hash'),
        'tags': lead.get('tag_ids') if isinstance(lead.get('tag_ids'), list) else [],
        'loyalty_tier': lead.get('x_loyalty_tier'),
        'loyalty_points': lead.get('x_loyalty_points'),
        'created_at': lead.get('create_date'),
        'last_seen_at': lead.get('write_date'),
    }


def run(vars: dict) -> dict:
    lead_payload = vars.get('odoo_lead_json') or vars.get('lead_payload')
    if lead_payload is None:
        return {
            'status': 'FAILED',
            'http_status': 400,
            'user_message': 'Missing required input: odoo_lead_json',
            'system_message': 'Tier 3.5 normalizer requires an Odoo lead payload.',
        }

    normalized = _normalize_customer_profile(lead_payload)
    return {
        'status': 'SUCCESS',
        'http_status': 200,
        'data': normalized,
        'user_message': 'Customer profile normalized successfully.',
        'system_message': 'Tier 3.5 normalization completed.',
    }
$PY$,
        'run',
        15, 64,
        1, 0, 'user',
        1, 0, 0, 1, 0,
        250, 'recipe-generator'
    WHERE NOT EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'normalize_customer_profile')
)
INSERT INTO cookbook_recipe_var (
    recipe_id, var_name, var_type, is_required, description, sort_order, created_by
)
SELECT r.id, v.var_name, v.var_type, v.is_required, v.description, v.sort_order, 'recipe-generator'
FROM cookbook_recipe r
CROSS JOIN (VALUES
    ('odoo_lead_json', 'string', 1, 'Raw Odoo lead payload in JSON format', 10)
) AS v(var_name, var_type, is_required, description, sort_order)
WHERE r.name = 'normalize_customer_profile'
ON CONFLICT (recipe_id, var_name) DO NOTHING;

INSERT INTO cookbook_recipe_output (
    recipe_id, output_key, source_path, value_type, is_required, description, display_label, sort_order, created_by
)
SELECT r.id, 'customer_id', 'data.customer_id', 'string', 1, 'Normalized customer identifier', 'Customer ID', 10, 'recipe-generator'
FROM cookbook_recipe r
WHERE r.name = 'normalize_customer_profile'
ON CONFLICT (recipe_id, output_key) DO NOTHING;

INSERT INTO cookbook_recipe_output (
    recipe_id, output_key, source_path, value_type, is_required, description, display_label, sort_order, created_by
)
SELECT r.id, 'customer_profile', 'data', 'object', 1, 'Normalized customer profile payload', 'Customer Profile', 20, 'recipe-generator'
FROM cookbook_recipe r
WHERE r.name = 'normalize_customer_profile'
ON CONFLICT (recipe_id, output_key) DO NOTHING;

COMMIT;
