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