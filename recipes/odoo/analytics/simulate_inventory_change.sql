-- Tier 5 Simulator: simulate_inventory_change
-- Applies hypothetical deltas to inventory snapshot in memory
-- Never writes to source system; result lives in session-scoped cache
-- Depends on CommonInventorySnapshot from normalizer

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
        'simulate_inventory_change',
        'Inventory What-If Simulator',
        'Tier 5 simulator: applies hypothetical qty deltas to cached inventory snapshot. Session-scoped; does not write to Odoo. Core of June 13 demo.',
        'tier5', 'session', 'CommonInventorySnapshot', 'CommonInventorySnapshot,DeltaAdjustments',
        (SELECT id FROM cookbook_system WHERE system_label = 'odoo'),
        (SELECT id FROM cookbook_module
           WHERE module_label = 'inventory'
             AND system_id = (SELECT id FROM cookbook_system WHERE system_label = 'odoo')),
        (SELECT id FROM cookbook_auth_profile WHERE profile_label = 'odoo_test'),
        NULL,
        $PY$
"""Tier 5 simulator: simulate_inventory_change

Reads `inventory_snapshot` and `delta_adjustments` (list of {product_id, qty_delta}),
applies deltas in memory and returns the modified snapshot. Does not write to source.
"""

import json
from copy import deepcopy
from datetime import datetime, timezone


def run(vars: dict) -> dict:
    try:
        snapshot = vars.get('inventory_snapshot')
        if snapshot is None:
            # try to load from normalizer if available
            try:
                from _normalizers.Inventory.normalize_inventory_snapshot import run as norm_run
                norm_res = norm_run({})
                if norm_res.get('status') != 'SUCCESS':
                    return norm_res
                snapshot = norm_res['data'].get('inventory_snapshot', [])
            except Exception:
                snapshot = []

        if not isinstance(snapshot, list):
            return {'status': 'VALIDATION_ERROR', 'http_status': 400, 'data': {}, 'user_message': 'inventory_snapshot must be a list.', 'system_message': 'Invalid inventory_snapshot.'}

        deltas = vars.get('delta_adjustments') or []
        if not isinstance(deltas, list):
            return {'status': 'VALIDATION_ERROR', 'http_status': 400, 'data': {}, 'user_message': 'delta_adjustments must be a list.', 'system_message': 'Invalid delta_adjustments.'}

        # Build lookup
        modified = deepcopy(snapshot)
        lookup = {item.get('product_id'): item for item in modified}

        for d in deltas:
            pid = d.get('product_id')
            if not pid:
                continue
            qty_delta = float(d.get('qty_delta') or 0)
            item = lookup.get(pid)
            if item:
                item['qty_available'] = round(float(item.get('qty_available') or 0) + qty_delta, 2)
                item['as_of'] = datetime.now(timezone.utc).isoformat()
            else:
                # create a synthetic snapshot entry for this product
                new = {
                    'product_id': pid,
                    'source_system': 'odoo',
                    'location_name': d.get('location_name') or 'unknown',
                    'qty_available': round(qty_delta, 2),
                    'qty_reserved': 0.0,
                    'qty_on_order': 0.0,
                    'reorder_point': float(d.get('reorder_point') or 0.0),
                    'as_of': datetime.now(timezone.utc).isoformat(),
                }
                modified.append(new)
                lookup[pid] = new

        # Return simulated snapshot in session context (engine handles Redis writes)
        return {
            'status': 'SUCCESS',
            'http_status': 200,
            'data': {'simulated_inventory_snapshot': modified},
            'user_message': 'Simulation applied to inventory snapshot.',
            'system_message': f'Applied {len(deltas)} delta(s).',
        }

    except Exception as exc:
        return {'status': 'UNKNOWN_ERROR', 'http_status': 500, 'data': {}, 'user_message': 'Simulation failed.', 'system_message': str(exc)}


if __name__ == '__main__':
    sample = run({'delta_adjustments': [{'product_id': 'prod:1001', 'qty_delta': 20}]})
    print(json.dumps(sample, indent=2))
$PY$,
        'run',
        30, 64,
        1, 0, 'user',
        1, 1,
        120, 'recipe-generator'
    WHERE NOT EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'simulate_inventory_change')
)

-- Add dependency: simulator depends on normalizer
INSERT INTO cookbook_recipe_dependency (
    recipe_id, depends_on_recipe_id, dependency_type, created_by
)
SELECT
    (SELECT id FROM cookbook_recipe WHERE name = 'simulate_inventory_change'),
    (SELECT id FROM cookbook_recipe WHERE name = 'normalize_inventory_snapshot'),
    'data',
    'recipe-generator'
WHERE NOT EXISTS (
    SELECT 1 FROM cookbook_recipe_dependency
    WHERE recipe_id = (SELECT id FROM cookbook_recipe WHERE name = 'simulate_inventory_change')
      AND depends_on_recipe_id = (SELECT id FROM cookbook_recipe WHERE name = 'normalize_inventory_snapshot')
);

-- Recipe vars
INSERT INTO cookbook_recipe_var (
    recipe_id, var_name, var_type, is_required, description, display_label, sort_order, created_by
)
SELECT r.id, v.var_name, v.var_type, v.is_required, v.description, v.display_label, v.sort_order, 'recipe-generator'
FROM cookbook_recipe r
CROSS JOIN (VALUES
    ('inventory_snapshot', 'object', 0, 'CommonInventorySnapshot list. If omitted, loads from cache.', 'Inventory Snapshot', 10),
    ('delta_adjustments', 'object', 1, 'List of {product_id, qty_delta, location_name (optional)}. Deltas to apply.', 'Delta Adjustments', 20)
) AS v(var_name, var_type, is_required, description, display_label, sort_order)
WHERE r.name = 'simulate_inventory_change'
ON CONFLICT (recipe_id, var_name) DO NOTHING;

COMMIT;
