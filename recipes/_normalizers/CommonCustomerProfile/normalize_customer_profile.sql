-- Tier 3.5 normalizer recipe registration for Odoo CRM leads.
-- Apply this against your kitchen database after the cookbook_recipe schema is available.

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
        tier, cache_scope, cdm_output_type, cdm_input_types_csv,
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
        'tier3.5', 'tenant', 'CommonCustomerProfile', NULL,
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
from typing import Any, Dict, Optional


def _first_nonempty(*values: Any) -> Optional[Any]:
    for value in values:
        if value is not None and value != "":
            return value
    return None


def _normalize_tags(tag_values: Any):
    if tag_values is None:
        return []
    if isinstance(tag_values, list):
        normalized = []
        for item in tag_values:
            if isinstance(item, dict) and "name" in item:
                normalized.append(str(item["name"]))
            elif item is not None:
                normalized.append(str(item))
        return normalized
    if isinstance(tag_values, dict) and "name" in tag_values:
        return [str(tag_values["name"]) ]
    if isinstance(tag_values, str):
        return [tag_values]
    return [str(tag_values)]


def _parse_lead_input(vars: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    if isinstance(vars.get("odoo_lead"), dict):
        return vars["odoo_lead"]
    if isinstance(vars.get("lead"), dict):
        return vars["lead"]
    data = vars.get("data")
    if isinstance(data, dict) and isinstance(data.get("lead"), dict):
        return data["lead"]
    lead_json = vars.get("odoo_lead_json")
    if isinstance(lead_json, str) and lead_json.strip():
        try:
            parsed = json.loads(lead_json)
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            return None
    return None


def _normalize_customer_profile(raw_lead: Dict[str, Any]) -> Dict[str, Any]:
    lead_id = raw_lead.get("id")
    customer_id = f"odoo:lead:{lead_id}" if lead_id is not None else None

    profile = {
        "customer_id": customer_id,
        "source_system": "odoo",
        "source_id": str(lead_id) if lead_id is not None else None,
        "name": _first_nonempty(raw_lead.get("name"), raw_lead.get("display_name")),
        "email": _first_nonempty(raw_lead.get("email_from"), raw_lead.get("email")),
        "phone": _first_nonempty(raw_lead.get("phone_mobile"), raw_lead.get("phone")),
        "face_hash": _first_nonempty(raw_lead.get("x_hyve_face_hash"), raw_lead.get("face_hash")),
        "tags": _normalize_tags(raw_lead.get("tag_ids") or raw_lead.get("tags")),
        "loyalty_tier": _first_nonempty(raw_lead.get("x_loyalty_tier"), raw_lead.get("loyalty_tier")),
        "loyalty_points": raw_lead.get("x_loyalty_points") or raw_lead.get("loyalty_points"),
        "created_at": _first_nonempty(raw_lead.get("create_date"), raw_lead.get("created_at")),
        "last_seen_at": _first_nonempty(raw_lead.get("write_date"), raw_lead.get("last_seen_at"), raw_lead.get("last_seen")),
    }
    return {k: v for k, v in profile.items() if v is not None}


def run(vars: Dict[str, Any]) -> Dict[str, Any]:
    raw_lead = _parse_lead_input(vars)
    if raw_lead is None:
        return {
            "status": "MISSING_INPUT",
            "http_status": 400,
            "data": {},
            "user_message": "No raw Odoo lead data was provided.",
            "system_message": "normalize_customer_profile requires odoo_lead or lead input.",
        }
    profile = _normalize_customer_profile(raw_lead)
    if not profile.get("customer_id"):
        return {
            "status": "VALIDATION_ERROR",
            "http_status": 400,
            "data": {},
            "user_message": "The Odoo lead record is missing an ID.",
            "system_message": "normalize_customer_profile could not derive customer_id.",
        }
    return {
        "status": "SUCCESS",
        "http_status": 200,
        "data": profile,
        "user_message": "Customer profile normalized successfully.",
        "system_message": "Tier 3.5 normalization completed.",
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
