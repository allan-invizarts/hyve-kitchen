-- Tier 3 recipe registration for the Odoo Stock/Inventory CRUD helper.
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
SELECT id, 'inventory', 'Stock / Inventory', 'Inventory/Stock module', 20, 'recipe-generator'
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
        tier, cache_scope, cdm_output_type, cdm_input_types_csv, invalidates_cache_csv,
        system_id, module_id, auth_profile_id, template_id,
        python_body, entrypoint,
        timeout_seconds, memory_mb,
        is_enabled, is_internal, required_role,
        is_read_only, is_getset, is_batch, is_chainable, is_render_card,
        expected_duration_ms, created_by
    )
    SELECT
        'odoo_inventory_crud',
        'Odoo Stock Quant CRUD',
        'CRUD helper for Odoo stock.quant records. Supports create, read, update, delete, and search actions.',
        'tier3', 'tenant', NULL, NULL, 'norm:inventory:*',
        (SELECT id FROM cookbook_system WHERE system_label = 'odoo'),
        (SELECT id FROM cookbook_module
           WHERE module_label = 'inventory'
             AND system_id = (SELECT id FROM cookbook_system WHERE system_label = 'odoo')),
        (SELECT id FROM cookbook_auth_profile WHERE profile_label = 'odoo_test'),
        NULL,
        $PY$
"""Odoo Stock/Inventory CRUD helper.

This Tier 3 recipe performs raw Odoo stock.quant operations through JSON-RPC.
Supported actions include create, read, update, delete, and search.
"""

import json
import random
import urllib.error
import urllib.request


def _json_rpc(url: str, service: str, method: str, *args):
    payload = {
        "jsonrpc": "2.0",
        "method": "call",
        "id": random.randint(1, 999999999),
        "params": {
            "service": service,
            "method": method,
            "args": list(args),
        },
    }
    req = urllib.request.Request(
        url=url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = json.load(resp)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP error: {e.code} {e.reason}")
    except Exception as e:
        raise RuntimeError(f"Network error: {e}")

    if body.get("error"):
        raise RuntimeError(body["error"])
    return body.get("result")


def _field_exists(url: str, db: str, uid: int, password: str, model: str, field_name: str) -> bool:
    try:
        _json_rpc(url, "object", "execute_kw", db, uid, password, model, "fields_get", [[field_name]])
        return True
    except RuntimeError:
        return False


def _normalize_stock_fields(vars: dict) -> dict:
    record = {}
    if "product_id" in vars:
        record["product_id"] = vars.get("product_id") or False
    if "location_id" in vars:
        record["location_id"] = vars.get("location_id") or False
    if "quantity" in vars:
        record["quantity"] = float(vars.get("quantity") or 0)
    if "reserved_quantity" in vars:
        record["reserved_quantity"] = float(vars.get("reserved_quantity") or 0)
    if "in_date" in vars:
        record["in_date"] = vars.get("in_date") or False
    return record


def _build_search_domain(vars: dict) -> list:
    product_id = vars.get("product_id")
    location_id = vars.get("location_id")
    in_stock = vars.get("in_stock")

    conditions = []
    if product_id:
        conditions.append(("product_id", "=", int(product_id)))
    if location_id:
        conditions.append(("location_id", "=", int(location_id)))
    if in_stock == "true":
        conditions.append(("quantity", ">", 0))
    elif in_stock == "false":
        conditions.append(("quantity", "<=", 0))

    if not conditions:
        return []
    if len(conditions) == 1:
        return [conditions[0]]
    return ["&"] + conditions if len(conditions) == 2 else conditions


def _search_quants(url: str, db: str, uid: int, password: str, fields: list, domain: list) -> list:
    if not domain:
        return []
    return _json_rpc(
        url,
        "object",
        "execute_kw",
        db,
        uid,
        password,
        "stock.quant",
        "search_read",
        [domain],
        {"fields": fields, "limit": 50},
    )


def _read_quant(url: str, db: str, uid: int, password: str, quant_id: int, fields: list) -> list:
    return _json_rpc(
        url,
        "object",
        "execute_kw",
        db,
        uid,
        password,
        "stock.quant",
        "read",
        [[quant_id]],
        {"fields": fields},
    )


def _create_quant(url: str, db: str, uid: int, password: str, record: dict) -> int:
    return _json_rpc(url, "object", "execute_kw", db, uid, password, "stock.quant", "create", [record])


def _update_quant(url: str, db: str, uid: int, password: str, quant_id: int, updates: dict) -> bool:
    return _json_rpc(url, "object", "execute_kw", db, uid, password, "stock.quant", "write", [[quant_id], updates])


def _delete_quant(url: str, db: str, uid: int, password: str, quant_id: int) -> bool:
    return _json_rpc(url, "object", "execute_kw", db, uid, password, "stock.quant", "unlink", [[quant_id]])


def _default_fields() -> list:
    return ["id", "product_id", "location_id", "quantity", "reserved_quantity", "in_date", "create_date", "write_date"]


def _get_effective_action(vars: dict) -> str:
    action = vars.get("action") or vars.get("crud_action") or "search"
    return str(action).strip().lower()


def run(vars: dict) -> dict:
    base_url = vars.get("odoo_base_url", "").rstrip("/")
    db = vars.get("odoo_db")
    uid = int(vars.get("odoo_uid") or 0)
    password = vars.get("odoo_password")
    url = f"{base_url}/jsonrpc"
    action = _get_effective_action(vars)

    fields = _default_fields()

    try:
        if action == "create":
            record = _normalize_stock_fields(vars)
            if not record:
                return {
                    "status": "VALIDATION_ERROR",
                    "http_status": None,
                    "data": {},
                    "user_message": "No quant fields provided for create.",
                    "system_message": "create requires at least one of product_id, location_id, quantity, reserved_quantity, or in_date.",
                }
            new_id = _create_quant(url, db, uid, password, record)
            new_rec = _read_quant(url, db, uid, password, new_id, fields)
            return {
                "status": "SUCCESS",
                "http_status": None,
                "data": {"quant_id": new_id, "quant": new_rec[0] if new_rec else {}},
                "user_message": "Stock quant created.",
                "system_message": "create executed.",
            }

        if action == "read":
            quant_id = int(vars.get("quant_id") or vars.get("id") or 0)
            if not quant_id:
                return {
                    "status": "VALIDATION_ERROR",
                    "http_status": None,
                    "data": {},
                    "user_message": "Quant ID is required for read.",
                    "system_message": "read requires quant_id or id.",
                }
            record = _read_quant(url, db, uid, password, quant_id, fields)
            return {
                "status": "SUCCESS",
                "http_status": None,
                "data": {"quant_id": quant_id, "quant": record[0] if record else {}},
                "user_message": "Stock quant read successfully.",
                "system_message": "read executed.",
            }

        if action == "update":
            quant_id = int(vars.get("quant_id") or vars.get("id") or 0)
            updates = _normalize_stock_fields(vars)
            if not quant_id or not updates:
                return {
                    "status": "VALIDATION_ERROR",
                    "http_status": None,
                    "data": {},
                    "user_message": "Quant ID and update fields are required for update.",
                    "system_message": "update requires quant_id/id and fields to change.",
                }
            _update_quant(url, db, uid, password, quant_id, updates)
            updated = _read_quant(url, db, uid, password, quant_id, fields)
            return {
                "status": "SUCCESS",
                "http_status": None,
                "data": {"quant_id": quant_id, "quant": updated[0] if updated else {}},
                "user_message": "Stock quant updated successfully.",
                "system_message": "update executed.",
            }

        if action == "delete":
            quant_id = int(vars.get("quant_id") or vars.get("id") or 0)
            if not quant_id:
                return {
                    "status": "VALIDATION_ERROR",
                    "http_status": None,
                    "data": {},
                    "user_message": "Quant ID is required for delete.",
                    "system_message": "delete requires quant_id or id.",
                }
            deleted = _delete_quant(url, db, uid, password, quant_id)
            return {
                "status": "SUCCESS",
                "http_status": None,
                "data": {"quant_id": quant_id, "deleted": bool(deleted)},
                "user_message": "Stock quant deleted successfully.",
                "system_message": "delete executed.",
            }

        if action == "search":
            domain = _build_search_domain(vars)
            result = _search_quants(url, db, uid, password, fields, domain)
            return {
                "status": "SUCCESS",
                "http_status": None,
                "data": {"quants": result},
                "user_message": "Search completed.",
                "system_message": "search executed.",
            }

        return {
            "status": "INVALID_ACTION",
            "http_status": 400,
            "data": {},
            "user_message": f"Unknown action: {action}",
            "system_message": f"Supported actions: create, read, update, delete, search",
        }

    except Exception as exc:
        return {
            "status": "UNKNOWN_ERROR",
            "http_status": None,
            "data": {},
            "user_message": "Failed to process Odoo stock quant CRUD action.",
            "system_message": str(exc),
        }
$PY$,
        'run',
        30, 64,
        1, 0, 'user',
        0, 1, 0, 1, 0,
        300, 'recipe-generator'
    WHERE NOT EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'odoo_inventory_crud')
)

INSERT INTO cookbook_recipe_var (
    recipe_id, var_name, var_type, is_required, description, display_label, sort_order, created_by
)
SELECT r.id, v.var_name, v.var_type, v.is_required, v.description, v.display_label, v.sort_order, 'recipe-generator'
FROM cookbook_recipe r
CROSS JOIN (VALUES
    ('odoo_base_url', 'string', 1, 'Odoo base URL', 'Odoo Base URL', 10),
    ('odoo_db', 'string', 1, 'Odoo database name', 'Odoo DB', 20),
    ('odoo_uid', 'integer', 1, 'Odoo user ID', 'Odoo UID', 30),
    ('odoo_password', 'string', 1, 'Odoo password', 'Odoo Password', 40),
    ('action', 'string', 0, 'CRUD action: create, read, update, delete, search', 'Action', 50),
    ('quant_id', 'integer', 0, 'Quant ID for read/update/delete actions', 'Quant ID', 60),
    ('product_id', 'integer', 0, 'Product ID for create/update/search actions', 'Product ID', 70),
    ('location_id', 'integer', 0, 'Location ID for create/update/search actions', 'Location ID', 80),
    ('quantity', 'float', 0, 'Quantity available for create/update actions', 'Quantity', 90),
    ('reserved_quantity', 'float', 0, 'Reserved quantity for create/update actions', 'Reserved Qty', 100),
    ('in_date', 'string', 0, 'IN date (YYYY-MM-DD format) for create/update actions', 'IN Date', 110),
    ('in_stock', 'string', 0, 'Filter for search: "true" (qty > 0) or "false" (qty <= 0)', 'In Stock Filter', 120)
) AS v(var_name, var_type, is_required, description, display_label, sort_order)
WHERE r.name = 'odoo_inventory_crud'
ON CONFLICT (recipe_id, var_name) DO NOTHING;

INSERT INTO cookbook_recipe_output (
    recipe_id, output_name, output_type, sort_order, created_by
)
SELECT r.id, 'quants', 'json_list', 10, 'recipe-generator'
FROM cookbook_recipe r
WHERE r.name = 'odoo_inventory_crud'
ON CONFLICT (recipe_id, output_name) DO NOTHING;

COMMIT;
