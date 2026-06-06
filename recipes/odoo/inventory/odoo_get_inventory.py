"""Tier 3 CRUD: Odoo Inventory getter.

Fetches inventory from Odoo stock module via JSON-RPC.
Falls back to sample mode if Odoo is unavailable.
"""

import json
import urllib.request
import urllib.error
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


def _fetch_from_odoo(config: dict) -> list:
    """Fetch inventory from Odoo stock.quant model via JSON-RPC.
    
    Expected config:
    - odoo_base_url: e.g. "http://localhost:8069"
    - odoo_db: database name
    - odoo_uid: user id
    - odoo_password: password
    - location_id (optional): filter by location
    """
    base_url = config.get("odoo_base_url", "http://localhost:8069")
    db = config.get("odoo_db", "odoo")
    uid = config.get("odoo_uid", 2)
    password = config.get("odoo_password", "admin")
    
    # RPC URL
    rpc_url = f"{base_url}/jsonrpc"
    
    # Search quant records
    # Note: User requires 'Inventory/User' group to access stock.quant.
    # If access denied, falls back to sample mode.
    search_payload = {
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
            "service": "object",
            "method": "execute_kw",
            "args": [
                db,
                uid,
                password,
                "stock.quant",
                "search_read",
                [],
            ],
            "kwargs": {
                "fields": ["product_id", "location_id", "quantity", "reserved_quantity", "in_date"],
                "limit": 100
            }
        },
        "id": 1
    }
    
    req = urllib.request.Request(
        rpc_url,
        data=json.dumps(search_payload).encode('utf-8'),
        headers={"Content-Type": "application/json"}
    )
    
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read().decode('utf-8'))
        
        if "error" in result and result["error"]:
            raise Exception(f"Odoo RPC error: {result['error']}")
        
        quants = result.get("result", [])
        
        # Transform to inventory format
        inventory = []
        now = datetime.utcnow().isoformat() + "Z"
        
        for q in quants:
            try:
                product_id = q.get("product_id")
                if not product_id:
                    continue
                
                # product_id is [id, name] from many2one field
                if isinstance(product_id, list):
                    prod_name = product_id[1] if len(product_id) > 1 else f"prod:{product_id[0]}"
                    prod_id = f"prod:{product_id[0]}"
                else:
                    prod_id = f"prod:{product_id}"
                    prod_name = str(product_id)
                
                location_id = q.get("location_id")
                loc_name = "Unknown"
                if isinstance(location_id, list) and len(location_id) > 1:
                    loc_name = location_id[1]
                
                inventory.append({
                    "product_id": prod_id,
                    "product_name": prod_name,
                    "source_system": "odoo",
                    "source_id": str(product_id[0] if isinstance(product_id, list) else product_id),
                    "location_name": loc_name,
                    "qty_available": float(q.get("quantity", 0.0)),
                    "qty_reserved": float(q.get("reserved_quantity", 0.0)),
                    "qty_on_order": 0.0,  # Would need to query purchase orders separately
                    "reorder_point": 0.0,  # Would need to query product template
                    "as_of": now,
                })
            except Exception:
                continue
        
        return inventory
    
    except urllib.error.URLError as e:
        raise Exception(f"Odoo connection failed: {e}")
    except json.JSONDecodeError as e:
        raise Exception(f"Invalid Odoo response: {e}")


def run(vars: dict) -> dict:
    """Fetch inventory from Odoo or return sample data.
    
    If Odoo config is provided, makes JSON-RPC call to stock.quant.
    Otherwise, returns sample inventory for testing.
    """
    try:
        # Check if real Odoo config provided
        if vars.get("odoo_base_url") or vars.get("use_odoo"):
            try:
                inventory = _fetch_from_odoo(vars)
                return {
                    "status": "SUCCESS",
                    "http_status": 200,
                    "data": {"inventory": inventory},
                    "user_message": f"Fetched {len(inventory)} items from Odoo.",
                    "system_message": f"odoo_get_inventory: Retrieved {len(inventory)} quants from stock.quant",
                }
            except Exception as e:
                # Fall back to sample mode if Odoo fails
                inventory = _sample_inventory()
                return {
                    "status": "SUCCESS",
                    "http_status": 200,
                    "data": {"inventory": inventory},
                    "user_message": "Odoo unavailable; returned sample inventory.",
                    "system_message": f"Odoo fallback: {str(e)}",
                }
        else:
            # Sample mode (no Odoo config)
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