-- Tier 3.5 Normalizer: normalize_inventory_snapshot
-- Transforms raw inventory into CommonInventorySnapshot CDM
-- Depends on odoo_get_inventory (Tier 3)

BEGIN;

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
        'normalize_inventory_snapshot',
        'Inventory Snapshot (Normalized)',
        'Tier 3.5 normalizer: consumes raw Odoo inventory and returns list[CommonInventorySnapshot]. Short TTL (60s) due to stock volatility.',
        'tier3.5', 'tenant', 'CommonInventorySnapshot', NULL,
        (SELECT id FROM cookbook_system WHERE system_label = 'odoo'),
        (SELECT id FROM cookbook_module
           WHERE module_label = 'inventory'
             AND system_id = (SELECT id FROM cookbook_system WHERE system_label = 'odoo')),
        (SELECT id FROM cookbook_auth_profile WHERE profile_label = 'odoo_test'),
        NULL,
        $PY$
"""Tier 3.5 normalizer: normalize_inventory_snapshot

Transforms raw inventory payloads into list[CommonInventorySnapshot].
"""

import json
from datetime import datetime


def _to_iso(dt):
    if not dt:
        return None
    if isinstance(dt, str):
        return dt
    try:
        return dt.isoformat()
    except Exception:
        return str(dt)


def run(vars: dict) -> dict:
    """Normalize raw inventory data.

    Accepts either:
      - vars['raw_inventory'] (list of raw dicts), or
      - if not provided, calls the Tier 3 `odoo.inventory.odoo_get_inventory.run` if available.

    Returns envelope with data['inventory_snapshot'] = list[CommonInventorySnapshot]
    """
    try:
        raw = vars.get('raw_inventory')
        if not raw:
            # attempt to load Tier 3 getter by file path (more robust in test env)
            try:
                import importlib.util
                from pathlib import Path
                recipes_path = Path(__file__).parents[3]
                get_path = recipes_path / 'recipes' / 'odoo' / 'inventory' / 'odoo_get_inventory.py'
                spec = importlib.util.spec_from_file_location('odoo_get_inventory', str(get_path))
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                res = module.run({})
                if res.get('status') != 'SUCCESS':
                    return res
                raw = res['data'].get('inventory', [])
            except Exception:
                raw = []

        normalized = []
        for r in raw:
            try:
                normalized.append({
                    'product_id': r.get('product_id') or r.get('source_id'),
                    'source_system': r.get('source_system', 'odoo'),
                    'location_name': r.get('location_name'),
                    'qty_available': float(r.get('qty_available') or 0.0),
                    'qty_reserved': float(r.get('qty_reserved') or 0.0),
                    'qty_on_order': float(r.get('qty_on_order') or 0.0),
                    'reorder_point': float(r.get('reorder_point') or 0.0),
                    'as_of': _to_iso(r.get('as_of')),
                })
            except Exception:
                continue

        return {
            'status': 'SUCCESS',
            'http_status': 200,
            'data': {'inventory_snapshot': normalized},
            'user_message': 'Normalized inventory snapshot.',
            'system_message': f'Normalized {len(normalized)} items.',
        }
    except Exception as exc:
        return {
            'status': 'UNKNOWN_ERROR',
            'http_status': 500,
            'data': {},
            'user_message': 'Failed to normalize inventory snapshot.',
            'system_message': str(exc),
        }


if __name__ == '__main__':
    print(json.dumps(run({}), indent=2))
$PY$,
        'run',
        30, 64,
        1, 0, 'user',
        1, 1,
        60, 'recipe-generator'
    WHERE NOT EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'normalize_inventory_snapshot')
)

-- Add dependency: normalizer depends on Tier 3 getter
INSERT INTO cookbook_recipe_dependency (
    recipe_id, depends_on_recipe_id, dependency_type, created_by
)
SELECT
    (SELECT id FROM cookbook_recipe WHERE name = 'normalize_inventory_snapshot'),
    (SELECT id FROM cookbook_recipe WHERE name = 'odoo_get_inventory'),
    'data',
    'recipe-generator'
WHERE NOT EXISTS (
    SELECT 1 FROM cookbook_recipe_dependency
    WHERE recipe_id = (SELECT id FROM cookbook_recipe WHERE name = 'normalize_inventory_snapshot')
      AND depends_on_recipe_id = (SELECT id FROM cookbook_recipe WHERE name = 'odoo_get_inventory')
);

-- Recipe vars
INSERT INTO cookbook_recipe_var (
    recipe_id, var_name, var_type, is_required, description, display_label, sort_order, created_by
)
SELECT r.id, v.var_name, v.var_type, v.is_required, v.description, v.display_label, v.sort_order, 'recipe-generator'
FROM cookbook_recipe r
CROSS JOIN (VALUES
    ('raw_inventory', 'object', 0, 'Optional: raw inventory list. If omitted, calls odoo_get_inventory.', 'Raw Inventory', 10)
) AS v(var_name, var_type, is_required, description, display_label, sort_order)
WHERE r.name = 'normalize_inventory_snapshot'
ON CONFLICT (recipe_id, var_name) DO NOTHING;

COMMIT;
