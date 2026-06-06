-- Tier 4 Analyzer: analyze_inventory_gaps
-- Identifies products below reorder point
-- Consumes CommonInventorySnapshot from Tier 3.5 normalizer

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
        'analyze_inventory_gaps',
        'Inventory Gap Analysis',
        'Tier 4 analyzer: consumes CommonInventorySnapshot CDM and returns products below reorder point. Drives purchasing recommendations.',
        'tier4', 'tenant', 'InventoryGapAnalysis', 'CommonInventorySnapshot',
        (SELECT id FROM cookbook_system WHERE system_label = 'odoo'),
        (SELECT id FROM cookbook_module
           WHERE module_label = 'inventory'
             AND system_id = (SELECT id FROM cookbook_system WHERE system_label = 'odoo')),
        (SELECT id FROM cookbook_auth_profile WHERE profile_label = 'odoo_test'),
        NULL,
        $PY$
"""Tier 4 analyzer: analyze_inventory_gaps

Consumes list[CommonInventorySnapshot] and returns products below reorder point.
"""

import json


def run(vars: dict) -> dict:
    try:
        snapshot = vars.get('inventory_snapshot') or vars.get('inventory')
        if not isinstance(snapshot, list):
            return {
                'status': 'VALIDATION_ERROR',
                'http_status': 400,
                'data': {},
                'user_message': 'inventory_snapshot is required (list).',
                'system_message': 'Expected list of CommonInventorySnapshot.',
            }

        gaps = []
        for item in snapshot:
            try:
                qty = float(item.get('qty_available') or 0.0)
                reorder = float(item.get('reorder_point') or 0.0)
                if qty < reorder:
                    gaps.append({
                        'product_id': item.get('product_id'),
                        'location_name': item.get('location_name'),
                        'qty_available': qty,
                        'reorder_point': reorder,
                        'gap': round(reorder - qty, 2),
                    })
            except Exception:
                continue

        return {
            'status': 'SUCCESS',
            'http_status': 200,
            'data': {'gaps': gaps, 'gap_count': len(gaps)},
            'user_message': 'Inventory gap analysis complete.',
            'system_message': f'Found {len(gaps)} gap(s).',
        }
    except Exception as exc:
        return {
            'status': 'UNKNOWN_ERROR',
            'http_status': 500,
            'data': {},
            'user_message': 'Failed to analyze inventory gaps.',
            'system_message': str(exc),
        }


if __name__ == '__main__':
    import sys
    import json
    print(json.dumps(run({'inventory_snapshot': []}), indent=2))
$PY$,
        'run',
        30, 64,
        1, 0, 'user',
        1, 1,
        120, 'recipe-generator'
    WHERE NOT EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'analyze_inventory_gaps')
)

-- Add dependency: analyzer depends on normalizer
INSERT INTO cookbook_recipe_dependency (
    recipe_id, depends_on_recipe_id, dependency_type, created_by
)
SELECT
    (SELECT id FROM cookbook_recipe WHERE name = 'analyze_inventory_gaps'),
    (SELECT id FROM cookbook_recipe WHERE name = 'normalize_inventory_snapshot'),
    'data',
    'recipe-generator'
WHERE NOT EXISTS (
    SELECT 1 FROM cookbook_recipe_dependency
    WHERE recipe_id = (SELECT id FROM cookbook_recipe WHERE name = 'analyze_inventory_gaps')
      AND depends_on_recipe_id = (SELECT id FROM cookbook_recipe WHERE name = 'normalize_inventory_snapshot')
);

-- Recipe vars
INSERT INTO cookbook_recipe_var (
    recipe_id, var_name, var_type, is_required, description, display_label, sort_order, created_by
)
SELECT r.id, v.var_name, v.var_type, v.is_required, v.description, v.display_label, v.sort_order, 'recipe-generator'
FROM cookbook_recipe r
CROSS JOIN (VALUES
    ('inventory_snapshot', 'object', 1, 'CommonInventorySnapshot list from normalizer', 'Inventory Snapshot', 10)
) AS v(var_name, var_type, is_required, description, display_label, sort_order)
WHERE r.name = 'analyze_inventory_gaps'
ON CONFLICT (recipe_id, var_name) DO NOTHING;

COMMIT;
