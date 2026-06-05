-- Tier 3 recipe registration for the Odoo CRM CRUD helper.
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
SELECT id, 'crm', 'Customer Relationship Management', 'CRM module', 10, 'recipe-generator'
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
        'odoo_crm_crud',
        'Odoo CRM Lead CRUD',
        'CRUD helper for Odoo crm.lead records. Supports create, read, update, delete, and search actions.',
        'tier3', 'tenant', NULL, NULL, 'norm:customer_profile:*,norm:customer_360:*',
        (SELECT id FROM cookbook_system WHERE system_label = 'odoo'),
        (SELECT id FROM cookbook_module
           WHERE module_label = 'crm'
             AND system_id = (SELECT id FROM cookbook_system WHERE system_label = 'odoo')),
        (SELECT id FROM cookbook_auth_profile WHERE profile_label = 'odoo_test'),
        NULL,
        $PY$
"""Odoo CRM lead CRUD helper.

This Tier 3 recipe performs raw Odoo crm.lead operations through JSON-RPC.
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


def _normalize_lead_fields(vars: dict) -> dict:
    record = {}
    if "lead_name" in vars:
        record["name"] = vars.get("lead_name") or False
    if "lead_email" in vars:
        record["email_from"] = vars.get("lead_email") or False
    if "lead_phone" in vars:
        record["phone"] = vars.get("lead_phone") or False
    face_hash = vars.get("face_hash")
    if face_hash:
        record["x_hyve_face_hash"] = face_hash
    return record


def _build_search_domain(vars: dict, use_face_hash: bool) -> list:
    email = vars.get("lead_email", "")
    phone = vars.get("lead_phone", "")
    face_hash = vars.get("face_hash", "") if use_face_hash else ""

    if face_hash:
        return ["|", "|", ("x_hyve_face_hash", "=", face_hash), ("email_from", "=", email), ("phone", "=", phone)]
    if email and phone:
        return ["|", ("email_from", "=", email), ("phone", "=", phone)]
    if email:
        return [("email_from", "=", email)]
    if phone:
        return [("phone", "=", phone)]
    return []


def _search_leads(url: str, db: str, uid: int, password: str, fields: list, domain: list) -> list:
    if not domain:
        return []
    return _json_rpc(
        url,
        "object",
        "execute_kw",
        db,
        uid,
        password,
        "crm.lead",
        "search_read",
        [domain],
        {"fields": fields, "limit": 10},
    )


def _read_lead(url: str, db: str, uid: int, password: str, lead_id: int, fields: list) -> list:
    return _json_rpc(
        url,
        "object",
        "execute_kw",
        db,
        uid,
        password,
        "crm.lead",
        "read",
        [[lead_id]],
        {"fields": fields},
    )


def _create_lead(url: str, db: str, uid: int, password: str, record: dict) -> int:
    return _json_rpc(url, "object", "execute_kw", db, uid, password, "crm.lead", "create", [record])


def _update_lead(url: str, db: str, uid: int, password: str, lead_id: int, updates: dict) -> bool:
    return _json_rpc(url, "object", "execute_kw", db, uid, password, "crm.lead", "write", [[lead_id], updates])


def _delete_lead(url: str, db: str, uid: int, password: str, lead_id: int) -> bool:
    return _json_rpc(url, "object", "execute_kw", db, uid, password, "crm.lead", "unlink", [[lead_id]])


def _default_fields(use_face_hash: bool) -> list:
    fields = ["id", "name", "email_from", "phone", "create_date", "write_date"]
    if use_face_hash:
        fields.append("x_hyve_face_hash")
    return fields


def _get_effective_action(vars: dict) -> str:
    action = vars.get("action") or vars.get("crud_action") or "get_or_create"
    return str(action).strip().lower()


def run(vars: dict) -> dict:
    base_url = vars.get("odoo_base_url", "").rstrip("/")
    db = vars.get("odoo_db")
    uid = int(vars.get("odoo_uid") or 0)
    password = vars.get("odoo_password")
    url = f"{base_url}/jsonrpc"
    action = _get_effective_action(vars)
    face_hash = vars.get("face_hash", "")
    use_face_hash = bool(face_hash) and _field_exists(url, db, uid, password, "crm.lead", "x_hyve_face_hash")

    fields = _default_fields(use_face_hash)

    try:
        if action == "create":
            record = _normalize_lead_fields(vars)
            if not record:
                return {
                    "status": "VALIDATION_ERROR",
                    "http_status": None,
                    "data": {},
                    "user_message": "No lead fields provided for create.",
                    "system_message": "create requires at least one of lead_name, lead_email, lead_phone, or face_hash.",
                }
            if use_face_hash and "x_hyve_face_hash" not in record and face_hash:
                record["x_hyve_face_hash"] = face_hash
            new_id = _create_lead(url, db, uid, password, record)
            new_rec = _read_lead(url, db, uid, password, new_id, fields)
            return {
                "status": "SUCCESS",
                "http_status": None,
                "data": {"lead_id": new_id, "lead": new_rec[0] if new_rec else {}},
                "user_message": "Lead created.",
                "system_message": "create executed.",
            }

        if action == "read":
            lead_id = int(vars.get("lead_id") or vars.get("id") or 0)
            if not lead_id:
                return {
                    "status": "VALIDATION_ERROR",
                    "http_status": None,
                    "data": {},
                    "user_message": "Lead ID is required for read.",
                    "system_message": "read requires lead_id or id.",
                }
            record = _read_lead(url, db, uid, password, lead_id, fields)
            return {
                "status": "SUCCESS",
                "http_status": None,
                "data": {"lead_id": lead_id, "lead": record[0] if record else {}},
                "user_message": "Lead read successfully.",
                "system_message": "read executed.",
            }

        if action == "update":
            lead_id = int(vars.get("lead_id") or vars.get("id") or 0)
            updates = _normalize_lead_fields(vars)
            if not lead_id or not updates:
                return {
                    "status": "VALIDATION_ERROR",
                    "http_status": None,
                    "data": {},
                    "user_message": "Lead ID and update fields are required for update.",
                    "system_message": "update requires lead_id/id and fields to change.",
                }
            if use_face_hash and "x_hyve_face_hash" not in updates and face_hash:
                updates["x_hyve_face_hash"] = face_hash
            _update_lead(url, db, uid, password, lead_id, updates)
            updated = _read_lead(url, db, uid, password, lead_id, fields)
            return {
                "status": "SUCCESS",
                "http_status": None,
                "data": {"lead_id": lead_id, "lead": updated[0] if updated else {}},
                "user_message": "Lead updated successfully.",
                "system_message": "update executed.",
            }

        if action == "delete":
            lead_id = int(vars.get("lead_id") or vars.get("id") or 0)
            if not lead_id:
                return {
                    "status": "VALIDATION_ERROR",
                    "http_status": None,
                    "data": {},
                    "user_message": "Lead ID is required for delete.",
                    "system_message": "delete requires lead_id or id.",
                }
            deleted = _delete_lead(url, db, uid, password, lead_id)
            return {
                "status": "SUCCESS",
                "http_status": None,
                "data": {"lead_id": lead_id, "deleted": bool(deleted)},
                "user_message": "Lead deleted successfully.",
                "system_message": "delete executed.",
            }

        if action == "search":
            domain = _build_search_domain(vars, use_face_hash)
            result = _search_leads(url, db, uid, password, fields, domain)
            return {
                "status": "SUCCESS",
                "http_status": None,
                "data": {"leads": result},
                "user_message": "Search completed.",
                "system_message": "search executed.",
            }

        domain = _build_search_domain(vars, use_face_hash)
        result = _search_leads(url, db, uid, password, fields, domain)
        if result:
            lead = result[0]
            return {
                "status": "SUCCESS",
                "http_status": None,
                "data": {"lead_id": lead.get("id"), "lead": lead},
                "user_message": "Lead retrieved successfully.",
                "system_message": "get_or_create executed.",
            }
        return {
            "status": "NOT_FOUND",
            "http_status": 404,
            "data": {},
            "user_message": "Lead not found.",
            "system_message": "get_or_create returned no lead.",
        }
    except Exception as exc:
        return {
            "status": "UNKNOWN_ERROR",
            "http_status": None,
            "data": {},
            "user_message": "Failed to process Odoo CRM lead CRUD action.",
            "system_message": str(exc),
        }
$PY$,
        'run',
        30, 64,
        1, 0, 'user',
        0, 1, 0, 1, 0,
        300, 'recipe-generator'
    WHERE NOT EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'odoo_crm_crud')
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
    ('action', 'string', 0, 'CRUD action: create, read, update, delete, search, get_or_create', 'Action', 50),
    ('lead_id', 'integer', 0, 'Lead ID for read/update/delete actions', 'Lead ID', 60),
    ('lead_name', 'string', 0, 'Lead name for create/update actions', 'Lead Name', 70),
    ('lead_email', 'string', 0, 'Lead email for create/update/search actions', 'Lead Email', 80),
    ('lead_phone', 'string', 0, 'Lead phone for create/update/search actions', 'Lead Phone', 90),
    ('face_hash', 'string', 0, 'Optional face hash to include in records if supported by the model', 'Face Hash', 100)
) AS v(var_name, var_type, is_required, description, display_label, sort_order)
WHERE r.name = 'odoo_crm_crud'
ON CONFLICT (recipe_id, var_name) DO NOTHING;

INSERT INTO cookbook_recipe_output (
    recipe_id, output_key, source_path, value_type, is_required, description, display_label, sort_order, created_by
)
SELECT r.id, 'lead_id', 'data.lead_id', 'integer', 0, 'Odoo lead record ID', 'Lead ID', 10, 'recipe-generator'
FROM cookbook_recipe r
WHERE r.name = 'odoo_crm_crud'
ON CONFLICT (recipe_id, output_key) DO NOTHING;

INSERT INTO cookbook_recipe_output (
    recipe_id, output_key, source_path, value_type, is_required, description, display_label, sort_order, created_by
)
SELECT r.id, 'lead', 'data.lead', 'object', 0, 'Odoo lead record payload', 'Lead', 20, 'recipe-generator'
FROM cookbook_recipe r
WHERE r.name = 'odoo_crm_crud'
ON CONFLICT (recipe_id, output_key) DO NOTHING;

COMMIT;
