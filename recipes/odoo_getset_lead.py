"""
Cookbook recipe: Get or Create Odoo Lead (Get/Set behavior)

This script is intended to be the rendered `python_body` stored in
`cookbook_recipe.python_body`. It expects runtime `vars` to include the
global connection vars (`odoo_base_url`, `odoo_db`, `odoo_uid`,
`odoo_password`) plus call-time vars (`lead_name`, `lead_email`,
`lead_phone`, `face_hash`).

Return envelope: see project conventions in SAMPLE templates.
"""
import json
import random
import urllib.request
import urllib.error


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


def run(vars: dict) -> dict:
    base_url = vars.get("odoo_base_url", "").rstrip("/")
    db = vars.get("odoo_db")
    uid = int(vars.get("odoo_uid") or 0)
    password = vars.get("odoo_password")
    url = f"{base_url}/jsonrpc"

    # Call-time vars
    lead_name = vars.get("lead_name", "")
    lead_email = vars.get("lead_email", "")
    lead_phone = vars.get("lead_phone", "")
    face_hash = vars.get("face_hash", "")

    # Only add the custom face-hash field if it exists on the model.
    use_face_hash = bool(face_hash) and _field_exists(url, db, uid, password, "crm.lead", "x_hyve_face_hash")
    if bool(face_hash) and not use_face_hash:
        face_hash = ""

    try:
        # Build search domain: prefer face_hash if present, fallback to email/phone
        if face_hash:
            # Search by face hash OR email OR phone
            domain = ["|", "|", ("x_hyve_face_hash", "=", face_hash), ("email_from", "=", lead_email), ("phone", "=", lead_phone)]
        else:
            if lead_email and lead_phone:
                domain = ["|", ("email_from", "=", lead_email), ("phone", "=", lead_phone)]
            elif lead_email:
                domain = [("email_from", "=", lead_email)]
            elif lead_phone:
                domain = [("phone", "=", lead_phone)]
            else:
                domain = []

        fields = ["id", "name", "email_from", "phone"]
        if use_face_hash:
            fields.append("x_hyve_face_hash")

        # search_read for existing lead (limit 1)
        if domain:
            result = _json_rpc(
                url,
                "object",
                "execute_kw",
                db,
                uid,
                password,
                "crm.lead",
                "search_read",
                [domain],
                {"fields": fields, "limit": 1},
            )
        else:
            result = []

        if result:
            lead = result[0]
            return {
                "status": "SUCCESS",
                "http_status": None,
                "data": {"lead_id": lead.get("id"), "lead": lead},
                "user_message": "Found existing lead",
                "system_message": "found by search_read",
            }

        # Not found -> create
        record = {
            "name": lead_name,
            "email_from": lead_email or False,
            "phone": lead_phone or False,
        }
        if use_face_hash:
            record["x_hyve_face_hash"] = face_hash

        new_id = _json_rpc(url, "object", "execute_kw", db, uid, password, "crm.lead", "create", [record])

        new_rec = _json_rpc(
            url,
            "object",
            "execute_kw",
            db,
            uid,
            password,
            "crm.lead",
            "read",
            [[new_id], {"fields": fields}],
        )

        return {
            "status": "SUCCESS",
            "http_status": None,
            "data": {"lead_id": new_id, "lead": new_rec[0] if new_rec else {}},
            "user_message": "Lead created",
            "system_message": "created via create",
        }

    except Exception as e:
        return {
            "status": "UNKNOWN_ERROR",
            "http_status": None,
            "data": {},
            "user_message": "Failed to query or create lead",
            "system_message": str(e),
        }
