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