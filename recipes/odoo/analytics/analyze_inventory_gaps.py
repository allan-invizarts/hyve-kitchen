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