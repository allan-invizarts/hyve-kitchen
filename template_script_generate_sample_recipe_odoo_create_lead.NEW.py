"""
INVISARTS API SCRIPT TEMPLATE
==============================

WHAT CHANGED FROM THE PRIOR template_script_generate_*.py:
  - This file is now the LITERAL TEXT that gets stored in the database
    in `cookbook_template.template_text`. The kitchen
    server reads this row, fills the Jinja2 placeholders below from the
    recipe metadata + var rows + output rows, and writes the rendered
    Python into `cookbook_recipe.python_body`.
  - Placeholders are Jinja2 ({{ recipe.x }} / {% for ... %}) instead of
    `REPLACE_WITH_X` literals.
  - The `STANDALONE_VARS = {...}` dict and `if __name__ == "__main__":`
    block from the prior version are GONE. The engine never reads them,
    and keeping them in the rendered python_body bloats the sandbox
    payload. For local testing, fetch the rendered body via
    `GET /v1/recipes/{id}` and wrap it with your own runner.
  - The `record = {...}` block is a `{% for field in recipe.field_mappings %}`
    loop so ONE template can spawn many recipes (odoo_create_lead,
    odoo_create_contact, odoo_create_opportunity, ...) each with their
    own field mapping.

HOW THE KITCHEN RENDERS IT:
  The generator POSTs to `POST /v1/recipes/from_template` with
      {
          "template_label": "odoo_crud_create",
          "recipe_metadata": {
              "name":              "odoo_create_lead",
              "display_name":      "Create Odoo CRM Lead",
              "description":       "Creates a new lead record in Odoo CRM.",
              "system_label":      "odoo",
              "module_label":      "crm",
              "auth_profile_label": "odoo_test",
              "target_model":      "crm.lead",
              "target_method":     "create",
              "primary_output_key": "lead_id",
              "field_mappings": [
                  {"api_field": "name",              "var_name": "lead_name",     "default_repr": "\"\""},
                  {"api_field": "type",              "var_name": "_lead_type",    "default_repr": "\"lead\""},
                  {"api_field": "email_from",        "var_name": "lead_email",    "default_repr": "\"\""},
                  {"api_field": "phone",             "var_name": "lead_phone",    "default_repr": "\"\""},
                  {"api_field": "partner_name",      "var_name": "lead_company",  "default_repr": "\"\""},
                  {"api_field": "description",       "var_name": "lead_notes",    "default_repr": "\"\""},
                  {"api_field": "priority",          "var_name": "lead_priority", "default_repr": "\"0\""},
                  {"api_field": "x_hyve_face_hash",  "var_name": "face_hash",     "default_repr": "\"\""}
              ]
          },
          "vars":    [ ... per-var rows (call_time inputs) ... ],
          "outputs": [ ... declared output keys ... ]
      }
  The endpoint renders THIS template against that context and INSERTs
  the rendered Python into cookbook_recipe.python_body in one transaction.

WHEN THE TEMPLATE IS EDITED:
  Call `POST /v1/recipes/{id}/rerender` to re-render every existing
  recipe that references this template_id (cookbook_recipe.template_id
  links them). The recipe gets a fresh cookbook_recipe_version row and
  V104 var/output snapshots.

RUNTIME CONTRACT (unchanged from the prior version):
  - The engine guarantees `vars` is a dict containing every variable
    declared in cookbook_recipe_var, validated + sanitized.
  - run(vars: dict) MUST return the envelope:
        {
            "status":         "SUCCESS" | "AUTH_FAILED" | "SERVER_TIMEOUT" |
                              "MALFORMED_RESPONSE" | "UNKNOWN_ERROR",
            "http_status":    int or None,
            "data":           dict of output values (keys must match
                              cookbook_recipe_output.output_key rows),
            "user_message":   str  -- customer-safe, non-technical,
            "system_message": str  -- technical detail for logs
        }
  - V103 envelope wrap will normalize bare returns into this shape,
    but recipes SHOULD return it natively.
"""

import json
import random
import urllib.request
import urllib.error


# ===========================================================================
# HELPER
# Self-contained -- kept inside the rendered body so the sandbox doesn't
# need any extra modules beyond the kitchen SDK.
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
        "id":      random.randint(1, 999_999_999),
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
    """{{ recipe.display_name }}

    {{ recipe.description }}

    Generated from cookbook_template 'odoo_crud_create' on {{ now_utc }}.
    """

    # --- Pull global creds (resolved from cookbook_global_var at runtime) --
    base_url = vars["odoo_base_url"].rstrip("/")
    db       = vars["odoo_db"]
    uid      = int(vars["odoo_uid"])
    password = vars["odoo_password"]
    url      = f"{base_url}/jsonrpc"

    # --- Build the record dict ---------------------------------------------
    # The {% for field in recipe.field_mappings %} loop below renders one
    # `"api_field": vars.get("var_name", default),` line per mapping
    # supplied in recipe_metadata.field_mappings. The default_repr is the
    # literal string the engine drops in (e.g. "\"\"" renders as "", and
    # "\"0\"" renders as "0").
    record = {
{% for field in recipe.field_mappings %}        "{{ field.api_field }}": vars.get("{{ field.var_name }}", {{ field.default_repr }}),
{% endfor %}    }
    # Strip empty optional fields so Odoo uses its own defaults.
    record = {k: v for k, v in record.items() if v != "" and v is not None}

    # --- Execute -----------------------------------------------------------
    try:
        result = _json_rpc(
            url,
            "object",
            "execute_kw",
            db, uid, password,
            "{{ recipe.target_model }}",
            "{{ recipe.target_method }}",
            [record],
            {},                     # keyword args -- empty for create
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
            "http_status":    200,
            "data":           {},
            "user_message":   "The Odoo server returned an error.",
            "system_message": msg,
        }

    # --- Validate the response shape ---------------------------------------
    if not isinstance(result, int):
        return {
            "status":         "MALFORMED_RESPONSE",
            "http_status":    200,
            "data":           {"raw_result": result},
            "user_message":   "Record may have been created but the response was unexpected.",
            "system_message": f"Expected int from {{ recipe.target_model }}.{{ recipe.target_method }}, got: {type(result).__name__}",
        }

    # --- Return the standard envelope --------------------------------------
    # primary_output_key is the cookbook_recipe_output row's output_key
    # that should hold this recipe's main return value. The engine
    # extracts every declared output from envelope.data into
    # kitchen_invocation_output rows for queryability.
    return {
        "status":         "SUCCESS",
        "http_status":    200,
        "data":           {
            "{{ recipe.primary_output_key }}": result,
            # Echo face_hash when supplied so the bridge can re-correlate
            # downstream commands to the originating vision event.
            "face_hash": vars.get("face_hash") or None,
        },
        "user_message":   f"{{ recipe.display_name }} succeeded. Odoo ID: {result}",
        "system_message": f"{{ recipe.target_model }}.{{ recipe.target_method }} returned id={result}",
    }
