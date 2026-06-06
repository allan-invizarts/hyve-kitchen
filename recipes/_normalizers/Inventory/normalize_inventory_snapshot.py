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