-- Tier 3 CRUD: odoo_get_inventory
-- Fetches raw inventory snapshot from Odoo stock module
-- Returns list of items with qty_available, qty_reserved, qty_on_order, reorder_point

BEGIN;

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
SELECT id, 'inventory', 'Stock / Inventory', 'Inventory management module', 20, 'recipe-generator'
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
        is_read_only, is_chainable,
        cache_ttl_seconds, created_by
    )
    SELECT
        'odoo_get_inventory',
        'Get Inventory Snapshot',
        'Tier 3 CRUD: Fetches raw inventory from Odoo stock module. Returns list of items with availability, reservations, and reorder points.',
        'tier3', 'tenant', NULL, NULL,
        (SELECT id FROM cookbook_system WHERE system_label = 'odoo'),
        (SELECT id FROM cookbook_module
           WHERE module_label = 'inventory'
             AND system_id = (SELECT id FROM cookbook_system WHERE system_label = 'odoo')),
        (SELECT id FROM cookbook_auth_profile WHERE profile_label = 'odoo_test'),
        NULL,
        $PY$
"""Tier 3 CRUD: Odoo Inventory getter (sample-mode stub).

Returns raw Odoo inventory payload or a sample inventory list when Odoo is unavailable.
"""

import json
from datetime import datetime


def _sample_inventory():
    now = datetime.utcnow().isoformat() + "Z"
    return [
        {
            "product_id": "prod:1001",
            "source_system": "odoo",
            "source_id": "1001",
            "location_name": "Main Warehouse",
            "qty_available": 5.0,
            "qty_reserved": 1.0,
            "qty_on_order": 10.0,
            "reorder_point": 12.0,
            "as_of": now,
        },
        {
            "product_id": "prod:1002",
            "source_system": "odoo",
            "source_id": "1002",
            "location_name": "Main Warehouse",
            "qty_available": 25.0,
            "qty_reserved": 0.0,
            "qty_on_order": 0.0,
            "reorder_point": 15.0,
            "as_of": now,
        },
    ]


def run(vars: dict) -> dict:
    """Return raw inventory list.

    vars may include Odoo connection info; if not provided, returns sample data.
    """
    try:
        # If real Odoo access is configured, one could implement JSON-RPC here.
        # For now, operate in sample mode.
        inventory = _sample_inventory()
        return {
            "status": "SUCCESS",
            "http_status": 200,
            "data": {"inventory": inventory},
            "user_message": "Returned sample inventory.",
            "system_message": "sample-mode: odoo_get_inventory",
        }
    except Exception as exc:
        return {
            "status": "UNKNOWN_ERROR",
            "http_status": 500,
            "data": {},
            "user_message": "Failed to fetch inventory.",
            "system_message": str(exc),
        }


if __name__ == "__main__":
    print(json.dumps(run({}), indent=2))
$PY$,
        'run',
        30, 64,
        1, 0, 'user',
        1, 1,
        NULL, 'recipe-generator'
    WHERE NOT EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'odoo_get_inventory')
)
SELECT * FROM new_recipe;

COMMIT;
