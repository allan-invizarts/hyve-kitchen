"""
INVISARTS API SCRIPT TEMPLATE
==============================
script_id:   REPLACE_WITH_GUID          e.g. 20260514120000001_CAT_xxxxxxxxx
name:        REPLACE_WITH_NAME          e.g. odoo_create_lead
target:      REPLACE_WITH_TARGET        e.g. odoo | weather | googlemaps | custom
category:    REPLACE_WITH_CATEGORY      e.g. crm | inventory | orders | events | email
description: REPLACE_WITH_DESCRIPTION  One sentence: what this does and why.

HOW THIS SCRIPT IS USED
------------------------
The engine fetches this text from api_scripts.script_text, then calls:

    run(vars: dict) -> dict

`vars` is a resolved dictionary of all variables — both call_time vars
(supplied by the LLM caller) and global_vars (pulled from the DB at runtime).

The engine guarantees that all variables declared in script_vars for this
script have been validated and sanitized before run() is called.

RETURN CONTRACT
---------------
run() must return a dict with these keys:

    {
        "status":         "SUCCESS" | "AUTH_FAILED" | "SERVER_TIMEOUT" |
                          "MALFORMED_RESPONSE" | "UNKNOWN_ERROR",
        "http_status":    int or None,
        "data":           dict of output values (keyed to match output_map),
        "user_message":   str  — customer-safe, non-technical,
        "system_message": str  — technical detail for logs
    }

STANDALONE TESTING
------------------
This script can also be run directly from the command line for testing:

    python odoo_create_lead.py

When run standalone, it reads vars from the STANDALONE_VARS dict below.
The run() function is identical in both modes — only the var source differs.
"""

import json
import random
import urllib.request
import urllib.error


# ===========================================================================
# STANDALONE TEST VARS
# Populated when running this script directly (not via the engine).
# In production, the engine injects vars from the DB + call_time inputs.
# Remove or leave empty before loading to DB — engine ignores this block.
# ===========================================================================
STANDALONE_VARS = {
    # global_vars — normally pulled from DB at runtime
    "odoo_base_url": "http://localhost:8069",
    "odoo_db":       "REPLACE_WITH_DB_NAME",
    "odoo_uid":      1,                       # integer user ID
    "odoo_password": "REPLACE_WITH_API_KEY_OR_PASSWORD",

    # call_time vars — normally provided by LLM caller
    "lead_name":     "Test Lead",
    "lead_email":    "test@example.com",
    "lead_phone":    "",
    "lead_company":  "",
    "lead_notes":    "",
    "lead_priority": "0",
    "face_hash":     "",  # optional Hyve-eyes face_id hash for attribution
}


# ===========================================================================
# HELPERS
# Keep helpers inside the script — it must be self-contained.
# ===========================================================================

def _json_rpc(url: str, service: str, method: str, *args) -> object:
    """
    Fire a single Odoo JSON-RPC call.
    Returns the 'result' field on success.
    Raises RuntimeError on RPC-level errors.
    """
    payload = {
        "jsonrpc": "2.0",
        "method":  "call",
        "id":      random.randint(1, 999999999),
        "params": {
            "service": service,
            "method":  method,
            "args":    list(args),
        },
    }
    req = urllib.request.Request(
        url=url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        body = json.loads(resp.read().decode("utf-8"))

    if body.get("error"):
        raise RuntimeError(json.dumps(body["error"]))

    return body["result"]


# ===========================================================================
# MAIN ENTRY POINT
# ===========================================================================

def run(vars: dict) -> dict:
    """
    Replace this docstring with what this specific script does.
    Template version — swap in your model, method, and field mapping below.
    """

    # --- Pull vars -----------------------------------------------------------
    base_url = vars["odoo_base_url"].rstrip("/")
    db       = vars["odoo_db"]
    uid      = int(vars["odoo_uid"])
    password = vars["odoo_password"]
    url      = f"{base_url}/jsonrpc"

    # --- Build the record dict -----------------------------------------------
    # Replace this section for each script. Map your vars to Odoo field names.
    # The x_hyve_face_hash example below shows the standard pattern for
    # attaching a Hyve-eyes face_hash to any Odoo record so subsequent
    # vision events can re-link to the same row.
    record = {
        "ODOO_FIELD_NAME":   vars.get("YOUR_VAR_NAME", ""),
        "x_hyve_face_hash":  vars.get("face_hash", ""),
        # add more fields here
    }
    # Remove empty optional fields so Odoo uses its own defaults
    record = {k: v for k, v in record.items() if v != ""}

    # --- Execute -------------------------------------------------------------
    try:
        result = _json_rpc(
            url,
            "object",
            "execute_kw",
            db, uid, password,
            "ODOO_MODEL_NAME",      # e.g. crm.lead
            "ODOO_METHOD_NAME",     # e.g. create
            [record],
            {},                     # keyword args — empty for create
        )
    except urllib.error.URLError as exc:
        return {
            "status":         "SERVER_TIMEOUT",
            "http_status":    None,
            "data":           {},
            "user_message":   "Could not reach the Odoo server.",
            "system_message": str(exc),
        }
    except RuntimeError as exc:
        msg = str(exc)
        status = "AUTH_FAILED" if "Access Denied" in msg else "UNKNOWN_ERROR"
        return {
            "status":         status,
            "http_status":    200,   # RPC errors still return HTTP 200
            "data":           {},
            "user_message":   "The Odoo server returned an error.",
            "system_message": msg,
        }

    # --- Map output ----------------------------------------------------------
    # Replace 'record_id' with whatever output_map.as declares for this script.
    # Echo face_hash so downstream commands can correlate this result with
    # the originating vision event.
    return {
        "status":         "SUCCESS",
        "http_status":    200,
        "data":           {
            "record_id": result,
            "face_hash": vars.get("face_hash") or None,
        },
        "user_message":   "Record created successfully.",
        "system_message": f"Result: {result}",
    }


# ===========================================================================
# STANDALONE RUNNER — only executes when run directly, not via engine
# ===========================================================================
if __name__ == "__main__":
    import sys

    print("=" * 60)
    print("STANDALONE MODE — using STANDALONE_VARS")
    print("=" * 60)

    response = run(STANDALONE_VARS)

    print(json.dumps(response, indent=2))

    if response["status"] != "SUCCESS":
        sys.exit(1)
