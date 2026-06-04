-- ============================================================================
-- INVISARTS -- odoo_create_lead INSERT (V103/V104 cookbook-evolution version)
-- ============================================================================
-- WHAT CHANGED FROM the prior odoo_create_lead_insert.sql:
--   - api_scripts        -> cookbook_recipe
--   - script_vars        -> cookbook_recipe_var
--   - global_vars        -> cookbook_global_var  (parent: cookbook_auth_profile)
--   - output_map JSONB   -> cookbook_recipe_output rows
--   - val_allowed_values -> cookbook_recipe_var_allowed_value rows
--   - masked_fields JSONB -> is_masked column on cookbook_recipe_var
--   - target_system/category strings -> system_id/module_id FKs
--   - auth_profile string -> auth_profile_id FK
--   - script_text        -> python_body
--   - script_id          -> id  (still VARCHAR(36) via generate_custom_guid)
--
-- ADDED in V103/V104 that weren't in the prior file:
--   - cookbook_recipe_version + V104 var/output_version snapshots (auto;
--     no INSERT here, kitchen.registry populates on every recipe create).
--   - cookbook_subscription_access row(s) so subscriptions can actually
--     use the recipe (deny-by-default since V103).
--   - is_render_card flag on the recipe (default 1, auto-render-card on).
--   - behaviour flags: is_read_only, is_getset, is_batch, is_chainable.
--
-- Re-run safety: every INSERT is keyed with WHERE NOT EXISTS / ON CONFLICT
-- DO NOTHING so you can apply this file repeatedly without duplicates.
--
-- Run with:
--   docker exec -i hyve-postgres psql -1 -U hyve_admin -d hyve_llm \
--     -f /sample/odoo_create_lead_insert.NEW.sql
-- ============================================================================

BEGIN;


-- ============================================================================
-- SECTION 1: cookbook_system  (was: literal 'target_system' string)
-- ----------------------------------------------------------------------------
-- Idempotent. The main seed (002_cookbook_evolution_seed.sql) already
-- inserts this row; included here so this file is self-contained.
-- ============================================================================
INSERT INTO cookbook_system (
    system_label, display_name, description, homepage_url, icon_filename,
    sort_order, created_by
) VALUES (
    'odoo', 'Odoo ERP',
    'Open-source ERP. Hyve integrates via Odoo''s JSON-RPC API.',
    'https://www.odoo.com',
    'odoo.svg', 10, 'recipe-generator'
)
ON CONFLICT (system_label) DO NOTHING;


-- ============================================================================
-- SECTION 2: cookbook_module  (was: literal 'category' string)
-- ----------------------------------------------------------------------------
-- One row per module per system. Idempotent on (system_id, module_label).
-- ============================================================================
INSERT INTO cookbook_module (
    system_id, module_label, display_name, description, sort_order, created_by
)
SELECT
    s.id, 'crm', 'Customer Relationship Management',
    'Leads, opportunities, contacts, pipeline stages.',
    10, 'recipe-generator'
FROM cookbook_system s
WHERE s.system_label = 'odoo'
ON CONFLICT (system_id, module_label) DO NOTHING;


-- ============================================================================
-- SECTION 3: cookbook_auth_profile + cookbook_global_var
-- ----------------------------------------------------------------------------
-- Was: 4 global_vars rows keyed by auth_profile = 'odoo_test'. Now: one
-- cookbook_auth_profile parent row + 4 cookbook_global_var rows pointing
-- at it via auth_profile_id FK.
--
-- min_edit_role gates GUI editing:
--     'super_admin' -- secrets (API keys, passwords)
--     'admin'       -- everything else
-- The plaintext + role-gate decision was deliberate; encryption-at-rest
-- via pgcrypto is documented as deferred item #14.
-- ============================================================================
INSERT INTO cookbook_auth_profile (
    system_id, profile_label, display_name, description, is_active,
    sort_order, created_by
)
SELECT s.id, 'odoo_test', 'Odoo - Test Instance',
       'Local docker-compose Odoo for development. REPLACE before production.',
       1, 10, 'recipe-generator'
FROM cookbook_system s
WHERE s.system_label = 'odoo'
ON CONFLICT (system_id, profile_label) DO NOTHING;

INSERT INTO cookbook_global_var (
    auth_profile_id, var_name, var_value, var_type,
    is_secret, min_edit_role, description, sort_order, created_by
)
SELECT p.id, v.var_name, v.var_value, v.var_type,
       v.is_secret, v.min_edit_role, v.description, v.sort_order,
       'recipe-generator'
FROM cookbook_auth_profile p
JOIN cookbook_system s ON s.id = p.system_id
CROSS JOIN (VALUES
    ('odoo_base_url', 'http://localhost:8069',     'url',    0, 'admin',
        'Base URL of the Odoo instance. No trailing slash.', 10),
    ('odoo_db',       'odoo',                      'string', 0, 'admin',
        'Odoo database name. Set during initial Odoo setup.', 20),
    ('odoo_uid',      '2',                         'int',    0, 'admin',
        'Odoo user ID integer. Settings > Users > (user) URL.', 30),
    ('odoo_password', 'REPLACE_WITH_REAL_API_KEY', 'secret', 1, 'super_admin',
        'Odoo API key. Edit gated to super_admin only.', 40)
) AS v(var_name, var_value, var_type, is_secret, min_edit_role, description, sort_order)
WHERE s.system_label = 'odoo' AND p.profile_label = 'odoo_test'
ON CONFLICT (auth_profile_id, var_name) DO NOTHING;


-- ============================================================================
-- SECTION 4: cookbook_template  (NEW -- didn't exist in the prior file)
-- ----------------------------------------------------------------------------
-- The Jinja2 source for odoo_crud_create. One template can spawn many
-- recipes (odoo_create_lead, odoo_create_contact, odoo_create_opportunity)
-- by binding it to different recipe_metadata.field_mappings + var rows.
--
-- The main seed already inserts this. Included here as IF NOT EXISTS so
-- this file works against a DB where the main seed hasn't been applied
-- (rare; the main seed is normally run first).
-- ============================================================================
INSERT INTO cookbook_template (
    system_id, template_label, display_name, description,
    template_text, template_engine, expected_signature,
    default_is_read_only, default_is_getset, default_is_batch, default_is_chainable,
    default_expected_duration_ms, sort_order, created_by
)
SELECT s.id, 'odoo_crud_create',
       'Odoo Generic CREATE via JSON-RPC',
       'Renders a recipe that creates one Odoo record. Caller supplies '
       'target_model + target_method + field_mappings via cookbook_recipe_var rows.',
       -- The Jinja2 source. Match what's in
       -- sample/template_script_generate_sample_recipe_odoo_create_lead.NEW.py
       -- so the developer's local template = the deployed template.
       'PLACEHOLDER_template_text_see_002_cookbook_evolution_seed.sql_for_canonical_source',
       'jinja2', 'vars_dict',
       0, 0, 0, 0, 800, 10, 'recipe-generator'
FROM cookbook_system s
WHERE s.system_label = 'odoo'
  AND NOT EXISTS (SELECT 1 FROM cookbook_template WHERE template_label = 'odoo_crud_create');


-- ============================================================================
-- SECTION 5: cookbook_recipe + initial cookbook_recipe_version
-- ----------------------------------------------------------------------------
-- Was: one api_scripts row with script_text holding the full Python source
-- and output_map JSONB. Now: cookbook_recipe row with python_body TEXT
-- (output_map is in section 7 as rows; arguments_schema is synthesized at
-- read time from cookbook_recipe_var rows in section 6).
--
-- The python_body below should be IDENTICAL to what the kitchen renders
-- from the template + recipe_metadata. For this hand-authored INSERT we
-- embed the rendered output directly; the generator pipeline can instead
-- POST to /v1/recipes/from_template and let the kitchen render it.
-- ============================================================================
WITH new_recipe AS (
    INSERT INTO cookbook_recipe (
        name, display_name, description,
        system_id, module_id, auth_profile_id, template_id,
        python_body, entrypoint,
        timeout_seconds, memory_mb,
        is_enabled, is_internal, required_role,
        is_read_only, is_getset, is_batch, is_chainable, is_render_card,
        expected_duration_ms, target_model, target_method,
        created_by
    )
    SELECT
        'odoo_create_lead',
        'Create Odoo CRM Lead',
        'Creates a new lead record in Odoo CRM with contact details, optional '
        'priority, notes, and an optional face_hash so the lead can be re-linked '
        'when the same person is seen again.',
        (SELECT id FROM cookbook_system WHERE system_label = 'odoo'),
        (SELECT id FROM cookbook_module
          WHERE module_label = 'crm'
            AND system_id = (SELECT id FROM cookbook_system WHERE system_label = 'odoo')),
        (SELECT id FROM cookbook_auth_profile WHERE profile_label = 'odoo_test'),
        (SELECT id FROM cookbook_template WHERE template_label = 'odoo_crud_create'),
        $PY$
"""Create Odoo CRM Lead

Creates a new lead record in Odoo CRM with contact details, optional
priority, notes, and an optional face_hash so the lead can be re-linked
when the same person is seen again.

Generated from cookbook_template 'odoo_crud_create'.
"""

import json
import random
import urllib.request
import urllib.error


def _json_rpc(url, service, method, *args):
    payload = {
        "jsonrpc": "2.0", "method": "call",
        "id": random.randint(1, 999_999_999),
        "params": {"service": service, "method": method, "args": list(args)},
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
    record = {k: v for k, v in record.items() if v != "" and v is not None}

    try:
        result = _json_rpc(
            url, "object", "execute_kw",
            db, uid, password,
            "crm.lead", "create",
            [record], {},
        )
    except urllib.error.URLError as exc:
        return {"status": "SERVER_TIMEOUT", "http_status": None, "data": {},
                "user_message": "Could not reach the Odoo server.",
                "system_message": str(exc)}
    except RuntimeError as exc:
        msg = str(exc)
        status = "AUTH_FAILED" if "Access Denied" in msg else "UNKNOWN_ERROR"
        return {"status": status, "http_status": 200, "data": {},
                "user_message": "The Odoo server returned an error.",
                "system_message": msg}

    if not isinstance(result, int):
        return {"status": "MALFORMED_RESPONSE", "http_status": 200,
                "data": {"raw_result": result},
                "user_message": "Lead may have been created but the response was unexpected.",
                "system_message": f"Expected int from crm.lead.create, got: {type(result).__name__}"}

    return {"status": "SUCCESS", "http_status": 200,
            "data": {"lead_id": result, "face_hash": vars.get("face_hash") or None},
            "user_message": f"Lead created successfully. Odoo ID: {result}",
            "system_message": f"crm.lead.create returned id={result}"}
$PY$,
        'run',
        30,    -- timeout_seconds
        512,   -- memory_mb
        1,     -- is_enabled
        0,     -- is_internal
        NULL,  -- required_role
        0,     -- is_read_only  (this is a write recipe)
        0,     -- is_getset
        0,     -- is_batch
        0,     -- is_chainable
        1,     -- is_render_card (V103 default = auto-render-card ON)
        800,   -- expected_duration_ms
        'crm.lead',
        'create',
        'recipe-generator'
    WHERE NOT EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'odoo_create_lead')
    RETURNING id, python_body, entrypoint
),
new_version AS (
    -- Initial cookbook_recipe_version row. The V104 hook in
    -- registry._snapshot_vars_and_outputs fires automatically AFTER the
    -- var + output rows below land, but for hand-authored INSERTs like
    -- this you have to call it via a post-INSERT step (or trust the
    -- next update_recipe / rerender to populate them). The main seed
    -- handles this; for this file we accept that the very first version
    -- has empty var/output snapshots.
    INSERT INTO cookbook_recipe_version (
        recipe_id, version_number, python_body, entrypoint,
        change_note, created_by
    )
    SELECT id, 1, python_body, entrypoint, 'initial seed', 'recipe-generator'
    FROM new_recipe
    RETURNING id, recipe_id
)
UPDATE cookbook_recipe r
SET current_version_id = v.id
FROM new_version v
WHERE r.id = v.recipe_id;


-- ============================================================================
-- SECTION 6: cookbook_recipe_var  (was: script_vars)
-- ----------------------------------------------------------------------------
-- Same shape as before plus: var_source ('call_time' vs 'global_vars'),
-- is_masked (replaces parent masked_fields JSONB), re_ask_if_missing +
-- re_ask_prompt (V103 LLM elicitation hook).
--
-- Global vars (odoo_base_url, odoo_db, odoo_uid, odoo_password) are NOT
-- in this table -- they live in cookbook_global_var (section 3) and are
-- resolved from the recipe's auth_profile_id at execution time.
-- ============================================================================
INSERT INTO cookbook_recipe_var (
    recipe_id, var_name, var_type, var_source, is_required, default_value,
    val_format, val_min_length, val_max_length,
    san_trim_whitespace, san_lowercase, san_strip_html,
    re_ask_if_missing, re_ask_prompt, is_masked,
    description, sort_order, created_by
)
SELECT r.id, v.var_name, v.var_type, 'call_time', v.is_required, v.default_value,
       v.val_format, v.val_min_length, v.val_max_length,
       v.san_trim, v.san_lower, v.san_strip,
       v.re_ask, v.re_ask_prompt, v.is_masked,
       v.description, v.sort_order, 'recipe-generator'
FROM cookbook_recipe r
CROSS JOIN (VALUES
    ('lead_name',     'string', 1, NULL,  NULL,    1,    255,  1, 0, 1,
     1, 'What is the name of this lead or opportunity?', 0,
     'Display name for the lead. Usually the contact full name or a short opportunity description.', 10),
    ('lead_email',    'string', 0, NULL,  'email', 5,    254,  1, 1, 0,
     0, NULL,                                          0,
     'Primary email address for the lead contact.', 20),
    ('lead_phone',    'string', 0, NULL,  'phone', 7,    30,   1, 0, 0,
     0, NULL,                                          0,
     'Phone number for the lead contact.', 30),
    ('lead_company',  'string', 0, NULL,  NULL,    1,    255,  1, 0, 1,
     0, NULL,                                          0,
     'Company or organization name for the lead.', 40),
    ('lead_notes',    'string', 0, '',    NULL,    NULL, 5000, 1, 0, 1,
     0, NULL,                                          0,
     'Free-text notes or description about the lead.', 50),
    ('lead_priority', 'string', 0, '0',   NULL,    NULL, NULL, 1, 0, 0,
     0, NULL,                                          0,
     'Odoo priority. 0=Normal 1=Low 2=High 3=Very High. Defaults to Normal.', 60),
    ('face_hash',     'string', 0, NULL,  NULL,    32,   128,  1, 1, 0,
     0, NULL,                                          0,
     'Hyve-eyes face_id hash for the person associated with this lead. Optional. When present, stored on x_hyve_face_hash custom field so subsequent badge/face events can re-attribute.', 70)
) AS v(var_name, var_type, is_required, default_value, val_format,
       val_min_length, val_max_length, san_trim, san_lower, san_strip,
       re_ask, re_ask_prompt, is_masked, description, sort_order)
WHERE r.name = 'odoo_create_lead'
ON CONFLICT (recipe_id, var_name) DO NOTHING;


-- ============================================================================
-- SECTION 6b: cookbook_recipe_var_allowed_value  (was: val_allowed_values JSONB)
-- ----------------------------------------------------------------------------
-- Was: '["0","1","2","3"]'::jsonb on the script_vars row. Now: one row
-- per allowed value, queryable + indexable + with optional display_label.
-- ============================================================================
INSERT INTO cookbook_recipe_var_allowed_value (
    recipe_var_id, allowed_value, display_label, sort_order, created_by
)
SELECT v.id, av.allowed_value, av.display_label, av.sort_order, 'recipe-generator'
FROM cookbook_recipe_var v
JOIN cookbook_recipe r ON r.id = v.recipe_id
CROSS JOIN (VALUES
    ('0', 'Normal',     10),
    ('1', 'Low',        20),
    ('2', 'High',       30),
    ('3', 'Very High',  40)
) AS av(allowed_value, display_label, sort_order)
WHERE r.name = 'odoo_create_lead'
  AND v.var_name = 'lead_priority'
ON CONFLICT (recipe_var_id, allowed_value) DO NOTHING;


-- ============================================================================
-- SECTION 7: cookbook_recipe_output  (was: output_map JSONB on api_scripts)
-- ----------------------------------------------------------------------------
-- One row per declared output key. The engine extracts each from
-- envelope.data into a kitchen_invocation_output row + uses display_label
-- as the field label on the auto-render-card image (V103 is_render_card).
-- ============================================================================
INSERT INTO cookbook_recipe_output (
    recipe_id, output_key, source_path, value_type, is_required,
    description, display_label, sort_order, created_by
)
SELECT r.id, o.output_key, o.source_path, o.value_type, o.is_required,
       o.description, o.display_label, o.sort_order, 'recipe-generator'
FROM cookbook_recipe r
CROSS JOIN (VALUES
    ('lead_id',   'data.lead_id',   'int',    1,
     'Odoo internal integer ID of the newly created lead record.', 'Lead ID',   10),
    ('face_hash', 'data.face_hash', 'string', 0,
     'Echo of the supplied face_hash, or null when not supplied. Useful for downstream commands that correlate back to the originating vision event.',
     'Face Hash', 20)
) AS o(output_key, source_path, value_type, is_required,
       description, display_label, sort_order)
WHERE r.name = 'odoo_create_lead'
ON CONFLICT (recipe_id, output_key) DO NOTHING;


-- ============================================================================
-- SECTION 8: cookbook_subscription_access  (NEW -- deny-by-default since V103)
-- ----------------------------------------------------------------------------
-- Without an explicit allow row, NO subscription can call this recipe.
-- The main seed grants kiosk-fleet system-level access to 'odoo' which
-- transitively allows this recipe; if you have a NEW subscription that
-- needs to call odoo_create_lead specifically, grant access here.
--
-- Two patterns:
--   1. System-level grant (recommended): the subscription can call EVERY
--      recipe under cookbook_system 'odoo'. Use when the sub is broadly
--      authorized for the integration.
--   2. Recipe-level grant: the subscription can call ONLY odoo_create_lead.
--      Use when the sub should be tightly scoped.
-- ============================================================================

-- Pattern 1 (system-level): uncomment + customize for a new subscription.
-- INSERT INTO cookbook_subscription_access (
--     subscription_id, system_id, access_action, reason, created_by
-- )
-- SELECT sub.id, sys.id, 'allow', 'recipe-generator grant for new sub', 'recipe-generator'
-- FROM subscription sub, cookbook_system sys
-- WHERE sub.subscription_name = 'my-new-subscription'
--   AND sys.system_label = 'odoo'
-- ON CONFLICT DO NOTHING;

-- Pattern 2 (recipe-level): demo only -- normally handled by the system-level
-- grant in the main seed. Uncomment to grant kiosk-fleet narrow access to
-- only odoo_create_lead (rather than every Odoo recipe).
-- INSERT INTO cookbook_subscription_access (
--     subscription_id, recipe_id, access_action, reason, created_by
-- )
-- SELECT sub.id, r.id, 'allow', 'narrow odoo_create_lead grant', 'recipe-generator'
-- FROM subscription sub, cookbook_recipe r
-- WHERE sub.subscription_name = 'kiosk-fleet' AND r.name = 'odoo_create_lead'
-- ON CONFLICT DO NOTHING;


COMMIT;


-- ============================================================================
-- VERIFICATION QUERIES (mirror the prior file's queries, updated for V103)
-- ============================================================================

-- 1. The recipe row (note: arguments_schema is synthesized at read time
--    from cookbook_recipe_var rows; the JSONB column doesn't exist).
SELECT r.name, r.display_name, s.system_label, m.module_label,
       ap.profile_label AS auth_profile,
       r.target_model, r.target_method,
       r.is_render_card, r.is_enabled
FROM cookbook_recipe r
LEFT JOIN cookbook_system s ON s.id = r.system_id
LEFT JOIN cookbook_module m ON m.id = r.module_id
LEFT JOIN cookbook_auth_profile ap ON ap.id = r.auth_profile_id
WHERE r.name = 'odoo_create_lead';

-- 2. Global vars resolved at runtime (was the same query against global_vars).
SELECT gv.var_name, gv.var_type, gv.is_secret, gv.min_edit_role, gv.description
FROM cookbook_global_var gv
JOIN cookbook_auth_profile ap ON ap.id = gv.auth_profile_id
WHERE ap.profile_label = 'odoo_test' AND gv.is_deleted = 0
ORDER BY gv.sort_order;

-- 3. Call-time vars + their allowed_value rows (replaces val_allowed_values JSONB).
SELECT v.var_name, v.var_type, v.is_required, v.default_value,
       v.val_format, v.re_ask_if_missing, v.is_masked,
       (SELECT string_agg(av.allowed_value, ',' ORDER BY av.sort_order)
          FROM cookbook_recipe_var_allowed_value av
         WHERE av.recipe_var_id = v.id AND av.is_deleted = 0
       ) AS allowed_values
FROM cookbook_recipe_var v
JOIN cookbook_recipe r ON r.id = v.recipe_id
WHERE r.name = 'odoo_create_lead' AND v.is_deleted = 0
ORDER BY v.sort_order;

-- 4. Declared outputs (was: output_map JSONB).
SELECT output_key, source_path, value_type, is_required, display_label
FROM cookbook_recipe_output o
JOIN cookbook_recipe r ON r.id = o.recipe_id
WHERE r.name = 'odoo_create_lead' AND o.is_deleted = 0
ORDER BY o.sort_order;

-- 5. Which subscriptions can call this recipe (NEW -- deny-by-default check).
SELECT sub.subscription_name,
       COALESCE(s.system_label, m.module_label, r2.name, et.trigger_name) AS grants_via,
       sa.access_action
FROM cookbook_subscription_access sa
JOIN subscription sub ON sub.id = sa.subscription_id
LEFT JOIN cookbook_system s ON s.id = sa.system_id
LEFT JOIN cookbook_module m ON m.id = sa.module_id
LEFT JOIN cookbook_recipe r2 ON r2.id = sa.recipe_id
LEFT JOIN cookbook_event_trigger et ON et.id = sa.event_trigger_id
WHERE sa.is_deleted = 0
  AND (s.system_label = 'odoo'
       OR (m.module_label = 'crm' AND m.system_id = (SELECT id FROM cookbook_system WHERE system_label = 'odoo'))
       OR r2.name = 'odoo_create_lead')
ORDER BY sub.subscription_name, grants_via;
