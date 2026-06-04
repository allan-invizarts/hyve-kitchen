-- ============================================================
-- INVISARTS — odoo_create_lead INSERT STATEMENTS
-- Generated: 2026-05-26
-- Fixed:
--   - updated_by/updated_date removed from explicit inserts
--     (schema DEFAULT NOW() handles them)
--   - DELETE before INSERT so file is safe to re-run
--   - Wrapped in BEGIN/COMMIT so it's all-or-nothing
--
-- Run with:
--   sudo -u postgres psql -d invisarts -f odoo_create_lead_insert.sql
-- ============================================================

BEGIN;

-- ============================================================
-- CLEANUP — delete in FK-safe order so re-runs never fail
-- ============================================================
-- 2026-05-27: re-run safety extended -- delete by script_id covers the new
-- face_hash row too (added in this revision).
DELETE FROM script_vars WHERE script_id = '20260508000000001_CRM_a1b2c3d4e';
DELETE FROM api_scripts  WHERE script_id = '20260508000000001_CRM_a1b2c3d4e';
DELETE FROM global_vars  WHERE auth_profile = 'odoo_test';


-- ============================================================
-- SECTION 1: api_scripts
-- One row for the script itself.
-- script_text holds the full Python source.
-- output_map is JSONB — lives here because it describes the
-- return shape, not the inputs.
-- ============================================================

INSERT INTO api_scripts (
    script_id,
    name,
    target_system,
    category,
    description,
    script_text,
    odoo_model,
    odoo_method,
    output_map,
    auth_profile,
    cache_ttl_seconds,
    is_read_only,
    is_batch,
    is_getset,
    is_chainable,
    expected_duration_ms,
    masked_fields,
    script_version,
    is_deleted,
    sort_order,
    changed_during_version,
    created_by,
    created_date
) VALUES (
    '20260508000000001_CRM_a1b2c3d4e',
    'odoo_create_lead',
    'odoo',
    'crm',
    'Creates a new lead record in Odoo CRM with contact details and optional priority and notes.',

    -- script_text: full Python source stored as text.
    -- The engine fetches this, calls run(vars), receives the return dict.
    $SCRIPT$
import json
import random
import urllib.request
import urllib.error


def _json_rpc(url: str, service: str, method: str, *args) -> object:
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
        raise RuntimeError(json.dumps(body["error"], indent=2))
    return body["result"]


def run(vars: dict) -> dict:
    base_url = vars["odoo_base_url"].rstrip("/")
    db       = vars["odoo_db"]
    uid      = int(vars["odoo_uid"])
    password = vars["odoo_password"]
    url      = f"{base_url}/jsonrpc"

    record = {
        "name":              vars["lead_name"],
        "type":              "lead",
        "email_from":        vars.get("lead_email",    ""),
        "phone":             vars.get("lead_phone",    ""),
        "partner_name":      vars.get("lead_company",  ""),
        "description":       vars.get("lead_notes",    ""),
        "priority":          vars.get("lead_priority", "0"),
        "x_hyve_face_hash":  vars.get("face_hash",     ""),
    }
    record = {k: v for k, v in record.items() if v != ""}

    try:
        result = _json_rpc(
            url, "object", "execute_kw",
            db, uid, password,
            "crm.lead", "create",
            [record], {},
        )
    except urllib.error.URLError as exc:
        return {
            "status": "SERVER_TIMEOUT", "http_status": None,
            "data": {}, "user_message": "Could not reach the Odoo server.",
            "system_message": str(exc),
        }
    except RuntimeError as exc:
        msg = str(exc)
        status = "AUTH_FAILED" if "Access Denied" in msg else "UNKNOWN_ERROR"
        return {
            "status": status, "http_status": 200,
            "data": {}, "user_message": "The Odoo server returned an error.",
            "system_message": msg,
        }

    if not isinstance(result, int):
        return {
            "status": "MALFORMED_RESPONSE", "http_status": 200,
            "data": {"raw_result": result},
            "user_message": "Lead may have been created but the response was unexpected.",
            "system_message": f"Expected int from crm.lead.create, got: {type(result).__name__} = {result}",
        }

    return {
        "status": "SUCCESS", "http_status": 200,
        "data": {
            "lead_id":   result,
            "face_hash": vars.get("face_hash") or None,
        },
        "user_message": f"Lead created successfully. Odoo ID: {result}",
        "system_message": f"crm.lead.create returned id={result}",
    }
$SCRIPT$,

    'crm.lead',
    'create',

    -- output_map: integer ID Odoo returns on create + optional face_hash echo
    '[
        {
            "source_field": "data.lead_id",
            "as": "lead_id",
            "type": "int",
            "required": true,
            "description": "Odoo internal integer ID of the newly created lead record."
        },
        {
            "source_field": "data.face_hash",
            "as": "face_hash",
            "type": "string",
            "required": false,
            "description": "Echo of the supplied face_hash, or null when not supplied. Useful for downstream commands that need to correlate back to the originating vision event."
        }
    ]'::jsonb,

    'odoo_test',   -- auth_profile
    NULL,          -- cache_ttl_seconds (writes are never cached)
    FALSE,         -- is_read_only
    FALSE,         -- is_batch
    FALSE,         -- is_getset
    FALSE,         -- is_chainable
    800,           -- expected_duration_ms
    '["odoo_password"]'::jsonb,  -- masked_fields
    1,             -- script_version
    FALSE,         -- is_deleted
    10,            -- sort_order
    NULL,          -- changed_during_version
    'tyler',
    '2026-05-08T00:00:00Z'
);


-- ============================================================
-- SECTION 2: global_vars
-- Four rows — the Odoo connection credentials.
-- Source = global_vars means the engine pulls these from here
-- at runtime. The LLM caller never supplies these.
--
-- NOTE: Replace REPLACE_WITH_REAL_API_KEY with your actual
-- Odoo API key before running in production.
-- ============================================================

INSERT INTO global_vars (
    var_id, var_name, target_system, auth_profile,
    var_value, var_type, description,
    is_deleted, sort_order, created_by, created_date
) VALUES
(
    '20260508000000010_GV_odoo_base_url',
    'odoo_base_url',
    'odoo',
    'odoo_test',
    'http://localhost:8069',
    'string',
    'Base URL of the Odoo instance. No trailing slash.',
    FALSE, 10, 'tyler', '2026-05-08T00:00:00Z'
),
(
    '20260508000000011_GV_odoo_db',
    'odoo_db',
    'odoo',
    'odoo_test',
    'odoo',
    'string',
    'Odoo database name. Set during initial Odoo setup.',
    FALSE, 20, 'tyler', '2026-05-08T00:00:00Z'
),
(
    '20260508000000012_GV_odoo_uid',
    'odoo_uid',
    'odoo',
    'odoo_test',
    '2',
    'int',
    'Odoo user ID integer. Found in Settings > Users > (user) URL.',
    FALSE, 30, 'tyler', '2026-05-08T00:00:00Z'
),
(
    '20260508000000013_GV_odoo_password',
    'odoo_password',
    'odoo',
    'odoo_test',
    'REPLACE_WITH_REAL_API_KEY',
    'secret',
    'Odoo API key. Created in Settings > Users > Account Security > New API Key.',
    FALSE, 40, 'tyler', '2026-05-08T00:00:00Z'
);


-- ============================================================
-- SECTION 3: script_vars
-- One row per call_time variable.
-- These are what the LLM caller supplies at invocation.
-- Global vars (section 2) are NOT repeated here —
-- they live in global_vars and are resolved by the engine.
-- ============================================================

INSERT INTO script_vars (
    var_id, script_id, name, var_type,
    is_required, source, default_value,
    val_format, val_min_length, val_max_length,
    val_min_value, val_max_value, val_pattern, val_allowed_values,
    san_trim_whitespace, san_lowercase, san_strip_html,
    re_ask_if_missing, re_ask_prompt,
    description,
    is_deleted, sort_order, created_by, created_date
) VALUES
(
    '20260508000000020_SV_lead_name',
    '20260508000000001_CRM_a1b2c3d4e',
    'lead_name',
    'string',
    TRUE,           -- required
    'call_time',
    NULL,           -- no default — required field
    NULL, 1, 255, NULL, NULL, NULL, NULL,
    TRUE, FALSE, TRUE,   -- trim, no lowercase, strip html
    TRUE,
    'What is the name of this lead or opportunity?',
    'Display name for the lead. Usually the contact full name or a short opportunity description.',
    FALSE, 10, 'tyler', '2026-05-08T00:00:00Z'
),
(
    '20260508000000021_SV_lead_email',
    '20260508000000001_CRM_a1b2c3d4e',
    'lead_email',
    'string',
    FALSE,          -- optional
    'call_time',
    NULL,
    'email', 5, 254, NULL, NULL, NULL, NULL,
    TRUE, TRUE, FALSE,   -- trim, lowercase, no strip html
    FALSE,
    'What is the contact email address for this lead?',
    'Primary email address for the lead contact.',
    FALSE, 20, 'tyler', '2026-05-08T00:00:00Z'
),
(
    '20260508000000022_SV_lead_phone',
    '20260508000000001_CRM_a1b2c3d4e',
    'lead_phone',
    'string',
    FALSE,
    'call_time',
    NULL,
    'phone', 7, 30, NULL, NULL, NULL, NULL,
    TRUE, FALSE, FALSE,
    FALSE,
    'What is the phone number for this lead?',
    'Phone number for the lead contact.',
    FALSE, 30, 'tyler', '2026-05-08T00:00:00Z'
),
(
    '20260508000000023_SV_lead_company',
    '20260508000000001_CRM_a1b2c3d4e',
    'lead_company',
    'string',
    FALSE,
    'call_time',
    NULL,
    NULL, 1, 255, NULL, NULL, NULL, NULL,
    TRUE, FALSE, TRUE,
    FALSE,
    'What company is this lead associated with?',
    'Company or organization name for the lead.',
    FALSE, 40, 'tyler', '2026-05-08T00:00:00Z'
),
(
    '20260508000000024_SV_lead_notes',
    '20260508000000001_CRM_a1b2c3d4e',
    'lead_notes',
    'string',
    FALSE,
    'call_time',
    '',             -- default empty string
    NULL, NULL, 5000, NULL, NULL, NULL, NULL,
    TRUE, FALSE, TRUE,
    FALSE,
    NULL,
    'Free-text notes or description about the lead.',
    FALSE, 50, 'tyler', '2026-05-08T00:00:00Z'
),
(
    '20260508000000025_SV_lead_priority',
    '20260508000000001_CRM_a1b2c3d4e',
    'lead_priority',
    'string',
    FALSE,
    'call_time',
    '0',            -- default Normal
    NULL, NULL, NULL, NULL, NULL, NULL,
    '["0", "1", "2", "3"]'::jsonb,
    TRUE, FALSE, FALSE,
    FALSE,
    NULL,
    'Odoo priority. 0=Normal 1=Low 2=High 3=Very High. Defaults to Normal.',
    FALSE, 60, 'tyler', '2026-05-08T00:00:00Z'
),
(
    '20260527000000026_SV_face_hash',
    '20260508000000001_CRM_a1b2c3d4e',
    'face_hash',
    'string',
    FALSE,          -- optional
    'call_time',
    NULL,
    NULL, 32, 128, NULL, NULL, NULL, NULL,   -- length range covers sha256 (64) + 0x prefix variants
    TRUE, TRUE, FALSE,   -- trim, lowercase, no strip_html
    FALSE,
    NULL,
    'Hyve-eyes face_id hash for the person associated with this lead. Optional. When present, stored on the lead as the x_hyve_face_hash custom field so subsequent badge / face sightings can re-attribute conversations to this same lead row.',
    FALSE, 70, 'tyler', '2026-05-27T00:00:00Z'
);


COMMIT;

-- ============================================================
-- VALIDATION QUERIES
-- Run these after inserting to confirm the schema holds
-- everything the script needs — no parsing required.
-- ============================================================

-- 1. The script row
SELECT script_id, name, target_system, category, auth_profile,
       script_version, expected_duration_ms
FROM api_scripts
WHERE name = 'odoo_create_lead';

-- 2. Global vars for this auth profile (what engine resolves at runtime)
SELECT var_name, var_type, auth_profile, description
FROM global_vars
WHERE auth_profile = 'odoo_test'
  AND is_deleted = FALSE
ORDER BY sort_order;

-- 3. Call-time vars for this script (what LLM caller must supply)
SELECT name, var_type, is_required, default_value,
       val_format, re_ask_if_missing, description
FROM script_vars
WHERE script_id = '20260508000000001_CRM_a1b2c3d4e'
  AND is_deleted = FALSE
ORDER BY sort_order;

-- 4. Output map (what the engine returns to the caller)
SELECT output_map
FROM api_scripts
WHERE name = 'odoo_create_lead';
