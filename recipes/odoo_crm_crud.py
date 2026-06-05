"""
Cookbook recipe: Odoo CRM Lead CRUD helper.

This script is intended to be the rendered `python_body` stored in
`cookbook_recipe.python_body`. It expects runtime `vars` to include the
global connection vars (`odoo_base_url`, `odoo_db`, `odoo_uid`,
`odoo_password`) plus call-time vars for lead operations.

Supported actions:
- `create`: create a new lead
- `read`: read a lead by `lead_id`
- `update`: update a lead by `lead_id`
- `delete`: delete a lead by `lead_id`
- `search`: search leads by email/phone/face_hash
- default: `get_or_create` fallback behavior

Return envelope: see project conventions in SAMPLE templates.
"""
import json
import random
import urllib.error
import urllib.request


def _json_rpc(url: str, service: str, method: str, *args) -> object:
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
                "user_message": "Found existing lead.",
                "system_message": "get_or_create found existing lead.",
            }

        record = _normalize_lead_fields(vars)
        if use_face_hash and "x_hyve_face_hash" not in record and face_hash:
            record["x_hyve_face_hash"] = face_hash
        new_id = _create_lead(url, db, uid, password, record)
        new_rec = _read_lead(url, db, uid, password, new_id, fields)
        return {
            "status": "SUCCESS",
            "http_status": None,
            "data": {"lead_id": new_id, "lead": new_rec[0] if new_rec else {}},
            "user_message": "Lead created.",
            "system_message": "get_or_create created new lead.",
        }

    except Exception as e:
        return {
            "status": "UNKNOWN_ERROR",
            "http_status": None,
            "data": {},
            "user_message": "Failed to process Odoo CRM lead CRUD action.",
            "system_message": str(e),
        }
