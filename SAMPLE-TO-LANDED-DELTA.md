# Sample schema → landed schema: delta reference for recipe authors

**Audience:** the developer generating recipes (currently authoring from
`Z:\work\claude-cowork\hyve\sample\proposed_sql_hyve_cookbook_recipes.sql`
and producing things like
`Z:\work\claude-cowork\hyve\sample\sample_recipe_odoo_create_lead.py`
and `Z:\work\claude-cowork\hyve\sample\odoo_create_lead_insert.sql`).

**Purpose:** This document maps every concept in the0
`proposed_sql_hyve_cookbook_recipes.sql` sample to its concrete name in
the landed `003_cookbook_evolution.sql` migration, so the developer can
re-target their generation scripts against the actual production schema
without guessing.

## Table-name mapping (sample → landed)

| Sample                  | Landed                                | Notes                                                                                                    |
|-------------------------|---------------------------------------|----------------------------------------------------------------------------------------------------------|
| `api_scripts`           | `cookbook_recipe`                     | "Cookbook holds the recipes; kitchen executes them." Same idea, renamed for the kitchen/cookbook theme. |
| `script_vars`           | `cookbook_recipe_var`                 | One-row-per-variable, queryable, individually updatable. Same shape as the sample.                       |
| `global_vars`           | `cookbook_global_var`                 | Plus a new parent `cookbook_auth_profile` table that groups vars by environment (odoo_test, odoo_prod). |
| `execution_log`         | `kitchen_invocation`                  | Kitchen IS the executor; execution log lives kitchen-side. Same audit semantics.                         |
| `system_config`         | `cookbook_system_config`              | Renamed for theme alignment. Seeded with sensible defaults in the migration itself.                      |
| (sample's `output_map` JSONB on api_scripts) | `cookbook_recipe_output` (rows) | Per "as few JSONB as possible" directive. One row per declared output key.                  |
| (sample's `val_allowed_values` JSONB on script_vars) | `cookbook_recipe_var_allowed_value` (rows) | Same reason. One row per enumerated permitted value.                |
| (sample's `masked_fields` JSONB on api_scripts) | `cookbook_recipe_var.is_masked` (column on var row) | Same reason. Mask flag lives ON the var rather than as a parallel list.        |

## Net-new tables (no analog in the sample)

These were added because the sample didn't model them and the kitchen
needs them to fulfil the wider vision (LLM-driven selection, deny-by-
default access, template-based generation, event-trigger storage).

| Landed table                      | Purpose                                                                                                       |
|-----------------------------------|---------------------------------------------------------------------------------------------------------------|
| `cookbook_system`                 | Top-level integration target (odoo, googlemaps, weather, hyve_vision, hyve_bridge, openai).                   |
| `cookbook_module`                 | Second-level grouping under a system (odoo.crm, odoo.stock, hyve_vision.face_id, etc.).                       |
| `cookbook_auth_profile`           | Named credential bundle (odoo_test, odoo_prod). One profile = N global_vars.                                  |
| `cookbook_template`               | DB-stored recipe template with Jinja2 placeholders. Renders into cookbook_recipe.python_body.                 |
| `cookbook_recipe_version`         | Append-only history of edits to a cookbook_recipe.                                                            |
| `cookbook_recipe_tag`             | Many-to-many tags for filterable recipe metadata. Used by LLM-driven selection (deferred item #13).           |
| `cookbook_event_trigger`          | DB-stored event-trigger plugins (counterpart to file-based hyve-cookbook/recipes/*.py). Fire-and-forget; runs IN the cookbook sidecar process, NOT sandboxed. |
| `cookbook_event_trigger_var`      | Per-payload-field metadata for an event trigger.                                                              |
| `cookbook_subscription_access`    | Per-subscription deny-by-default access control to systems / modules / recipes / event_triggers.              |
| `kitchen_invocation_var`          | Per-invocation arg snapshot. Replaces the sample's `execution_log.input_vars_received` + `input_vars_sanitized` JSONB. |
| `kitchen_invocation_output`       | Per-invocation declared-output snapshot. Replaces `execution_log.response_mapped` JSONB.                      |
| `kitchen_invocation_validation_error` | One row per validation failure. Replaces `execution_log.validation_errors` JSONB.                          |
| `kitchen_invocation_job`          | Async job queue (kitchen V102; predates this proposal but referenced by the deferred-features doc).           |
| `kitchen_artifact`                | Files/images produced during an invocation (PNG cards, charts).                                               |

## Column-level deltas on the renamed tables

### `api_scripts` → `cookbook_recipe`

| Sample column            | Landed column                | Status / notes                                                          |
|--------------------------|------------------------------|-------------------------------------------------------------------------|
| `script_id`              | `id`                         | PK `VARCHAR(36)` defaulting to `generate_custom_guid('KTN')`.            |
| `name`                   | `name`                       | unchanged.                                                              |
| `target_system`          | `system_id` (FK)             | replaced string with FK into `cookbook_system`.                          |
| `category`               | `module_id` (FK)             | replaced string with FK into `cookbook_module`.                          |
| `description`            | `description`                | unchanged.                                                              |
| `script_text`            | `python_body`                | renamed for kitchen consistency (matches existing kitchen_recipe).       |
| `odoo_model`             | `target_model`               | renamed (generalised; not Odoo-specific).                                |
| `odoo_method`            | `target_method`              | renamed (generalised).                                                  |
| `output_map` JSONB       | `cookbook_recipe_output` rows | LIFTED OUT to its own table.                                            |
| `auth_profile` (string)  | `auth_profile_id` (FK)       | FK to `cookbook_auth_profile`.                                          |
| `cache_ttl_seconds`      | `cache_ttl_seconds`          | unchanged. Already existed on the original `kitchen_recipe`.             |
| `is_read_only`           | `is_read_only`               | unchanged.                                                              |
| `is_batch`               | `is_batch`                   | unchanged.                                                              |
| `is_getset`              | `is_getset`                  | unchanged.                                                              |
| `is_chainable`           | `is_chainable`               | unchanged.                                                              |
| (none)                   | `is_render_card`             | NEW. Default 1. Engine auto-renders a card image when 1.                 |
| `expected_duration_ms`   | `expected_duration_ms`       | unchanged.                                                              |
| `masked_fields` JSONB    | `cookbook_recipe_var.is_masked` | MOVED to per-var column.                                              |
| `script_version`         | `current_version_id` (FK)    | replaced int with FK to `cookbook_recipe_version` (full history).        |
| (none)                   | `template_id` (FK, nullable) | NEW. Points at the template that generated this recipe (when applicable). |
| audit cols               | audit cols                   | unchanged. `is_deleted INTEGER 0|1` (not BOOLEAN, matches blackbox convention). |

### `script_vars` → `cookbook_recipe_var`

| Sample column            | Landed column                | Status / notes                                                          |
|--------------------------|------------------------------|-------------------------------------------------------------------------|
| `var_id`                 | `id`                         | PK `VARCHAR(36)` defaulting to `generate_custom_guid('CRV')`.            |
| `script_id`              | `recipe_id` (FK)             | renamed to match the renamed parent.                                    |
| `name`                   | `var_name`                   | renamed to disambiguate from row-level "name" semantics.                 |
| `var_type`               | `var_type`                   | unchanged.                                                              |
| `is_required`            | `is_required`                | unchanged. INT not BOOLEAN (blackbox convention).                        |
| `source`                 | `var_source`                 | renamed (avoids reserved-word ambiguity).                                |
| `default_value`          | `default_value`              | unchanged.                                                              |
| `val_format`             | `val_format`                 | unchanged.                                                              |
| `val_min_length`         | `val_min_length`             | unchanged.                                                              |
| `val_max_length`         | `val_max_length`             | unchanged.                                                              |
| `val_min_value`          | `val_min_value`              | unchanged.                                                              |
| `val_max_value`          | `val_max_value`              | unchanged.                                                              |
| `val_pattern`            | `val_pattern`                | unchanged.                                                              |
| `val_allowed_values` JSONB | `cookbook_recipe_var_allowed_value` rows | LIFTED OUT.                                                  |
| `san_trim_whitespace`    | `san_trim_whitespace`        | unchanged. INT not BOOLEAN.                                              |
| `san_lowercase`          | `san_lowercase`              | unchanged.                                                              |
| `san_strip_html`         | `san_strip_html`             | unchanged.                                                              |
| `re_ask_if_missing`      | `re_ask_if_missing`          | unchanged.                                                              |
| `re_ask_prompt`          | `re_ask_prompt`              | unchanged.                                                              |
| (none on per-var)        | `is_masked`                  | NEW. Replaces parent's `masked_fields` JSONB.                            |
| `description`            | `description`                | unchanged. NOT NULL (it IS the documentation).                           |
| audit cols               | audit cols                   | unchanged.                                                              |

### `global_vars` → `cookbook_global_var`

| Sample column            | Landed column                | Status / notes                                                          |
|--------------------------|------------------------------|-------------------------------------------------------------------------|
| `var_id`                 | `id`                         | PK uses `generate_custom_guid('CGV')`.                                  |
| `var_name`               | `var_name`                   | unchanged.                                                              |
| `target_system`          | (derived via FK)             | dropped: lookup via `auth_profile.system_id`.                            |
| `auth_profile`           | `auth_profile_id` (FK)       | FK to new `cookbook_auth_profile` table.                                 |
| `var_value`              | `var_value`                  | unchanged. PLAINTEXT (not encrypted). GUI-edit gated by `min_edit_role`. |
| `var_type`               | `var_type`                   | unchanged.                                                              |
| (none)                   | `is_secret`                  | NEW. Mark for redaction in logs + UI display.                            |
| (none)                   | `min_edit_role`              | NEW. Restricts GUI edits (super_admin / admin / trainer / user / viewer). |
| `description`            | `description`                | unchanged.                                                              |
| `expires_at`             | `expires_date`               | renamed to match `_date` convention.                                     |
| audit cols               | audit cols                   | unchanged.                                                              |

### `execution_log` → `kitchen_invocation` (+ child tables)

| Sample column                | Landed column / table                          | Status / notes                                                          |
|------------------------------|-----------------------------------------------|-------------------------------------------------------------------------|
| `execution_id`               | `kitchen_invocation.id`                       | PK `generate_custom_guid('KTI')`.                                       |
| `script_id`                  | `kitchen_invocation.recipe_id` (FK)           | renamed.                                                                |
| `parent_execution_id`        | `kitchen_invocation.parent_invocation_id` (FK self) | renamed.                                                          |
| `session_id`                 | `kitchen_invocation.session_id`               | unchanged.                                                              |
| `resolved_endpoint`          | (not stored explicitly)                       | dropped -- recipe code dictates the endpoint; `kitchen_invocation.raw_result_text` debug blob covers post-mortem inspection. |
| `resolved_body`              | (not stored explicitly)                       | dropped -- same reason.                                                  |
| `input_vars_received` JSONB  | `kitchen_invocation_var.raw_value` (per-var rows) | LIFTED OUT.                                                         |
| `input_vars_sanitized` JSONB | `kitchen_invocation_var.sanitized_value`      | LIFTED OUT into same row.                                               |
| `status`                     | `kitchen_invocation.status`                   | unchanged enum string.                                                  |
| `http_status_code`           | (not stored as separate column)               | rolled into `kitchen_invocation.raw_result_text` envelope; query via `result.envelope.http_status`. |
| `response_raw` JSONB         | `kitchen_invocation.raw_result_text` TEXT     | demoted to plain TEXT debug blob; not indexed.                          |
| `response_mapped` JSONB      | `kitchen_invocation_output` rows              | LIFTED OUT into per-output rows.                                        |
| `validation_errors` JSONB    | `kitchen_invocation_validation_error` rows    | LIFTED OUT.                                                             |
| `user_message`               | `kitchen_invocation.user_message`             | unchanged. NEW on the kitchen side; matches sample.                      |
| `system_message`             | `kitchen_invocation.error_message`            | renamed to match kitchen's existing column.                              |
| `recommended_action`         | `kitchen_invocation.recommended_action`       | NEW, matches sample.                                                    |
| `duration_ms`                | `kitchen_invocation.duration_ms`              | unchanged.                                                              |
| `cache_hit`                  | `kitchen_invocation.cache_hit`                | unchanged.                                                              |
| audit cols                   | audit cols                                    | unchanged. (Note: kitchen_invocation IS still soft-deletable; sample said "immutable" but the landed schema keeps soft-delete for ops consistency.) |

### `system_config` → `cookbook_system_config`

| Sample column         | Landed column                | Status / notes                                              |
|-----------------------|------------------------------|-------------------------------------------------------------|
| `config_key`          | `config_key`                 | unchanged. UNIQUE.                                          |
| `config_value`        | `config_value`               | unchanged.                                                  |
| `value_type`          | `value_type`                 | unchanged. Added `json_text` to the allowed set.            |
| `description`         | `description`                | unchanged.                                                  |
| (none)                | `min_edit_role`              | NEW. Same role gate as `cookbook_global_var`.               |
| audit cols            | audit cols                   | unchanged.                                                  |

## Sample recipe Python: `def run(vars: dict)` convention

The sample's `def run(vars: dict) -> dict` calling convention is supported,
but **the kitchen sandbox worker was historically calling `fn(**arguments)`
(kwargs unpacking)**. The Patch 1 follow-up to `kitchen/sandbox/worker.py`
inspects the function signature and dispatches accordingly:

```python
import inspect
sig = inspect.signature(fn)
params = list(sig.parameters.values())
if (len(params) == 1
        and params[0].name == "vars"
        and params[0].kind in (inspect.Parameter.POSITIONAL_OR_KEYWORD,
                               inspect.Parameter.POSITIONAL_ONLY)):
    result = fn(arguments)         # sample convention
else:
    result = fn(**arguments)       # existing kitchen recipes
```

Both styles work side by side. Recipes generated from the sample template
keep `def run(vars: dict) -> dict`; existing kitchen recipes like
`warehouse_low_stock(threshold=10, ...)` keep their kwargs style.

## Sample recipe envelope: standardized return shape

The sample's return contract:

```python
{
    "status":         "SUCCESS" | "AUTH_FAILED" | "SERVER_TIMEOUT" |
                      "MALFORMED_RESPONSE" | "UNKNOWN_ERROR",
    "http_status":    int | None,
    "data":           dict of output values (keyed to match output_map),
    "user_message":   str,    # customer-safe
    "system_message": str     # technical
}
```

is enforced by the kitchen Patch 2 follow-up to `routes/cook.py`: any
recipe return is normalized into this envelope before being persisted to
`kitchen_invocation` and returned in `CookResponse`. The fields map to
columns:

* `status` -> `kitchen_invocation.status` (enum string)
* `http_status` -> embedded in `kitchen_invocation.raw_result_text` (not its own column)
* `data` -> exploded into `kitchen_invocation_output` rows (one per declared `cookbook_recipe_output`)
* `user_message` -> `kitchen_invocation.user_message`
* `system_message` -> `kitchen_invocation.error_message`

Recipes that return a bare value (not the envelope) are wrapped
automatically: `{"status": "SUCCESS", "data": {<first_output>: value}, ...}`.

## GUIDs

Use `generate_custom_guid('XXX')` for every ID. The 3-letter code
indicates table type at a glance. The codes used in this round:

| Table                                | Code |
|--------------------------------------|------|
| cookbook_recipe                      | KTN  |
| cookbook_recipe_version              | KTV  |
| cookbook_recipe_tag                  | KTT  |
| cookbook_recipe_var                  | CRV  |
| cookbook_recipe_var_allowed_value    | CVA  |
| cookbook_recipe_output               | CRO  |
| cookbook_system                      | CSY  |
| cookbook_module                      | CMD  |
| cookbook_auth_profile                | CAP  |
| cookbook_global_var                  | CGV  |
| cookbook_template                    | CTM  |
| cookbook_event_trigger               | CET  |
| cookbook_event_trigger_var           | CTV  |
| cookbook_subscription_access         | CSA  |
| cookbook_system_config               | CSC  |
| kitchen_invocation                   | KTI  |
| kitchen_invocation_job               | KIJ  |
| kitchen_invocation_var               | KVR  |
| kitchen_invocation_output            | KVO  |
| kitchen_invocation_validation_error  | KVE  |
| kitchen_artifact                     | KTA  |
| bridge_event_subscription            | BES  |

## What the recipe-generating developer needs to change in their pipeline

1. **Change every reference to `api_scripts` to `cookbook_recipe`**.
   `script_text` is now `python_body`; `script_id` is now `id`.
2. **Change `script_vars` to `cookbook_recipe_var`**.
   `var_id`/`script_id`/`name`/`source` become `id`/`recipe_id`/`var_name`/`var_source`.
3. **Stop INSERTing into `script_vars.val_allowed_values` JSONB**.
   Insert one row per allowed value into `cookbook_recipe_var_allowed_value` instead.
4. **Stop INSERTing into `api_scripts.output_map` JSONB**.
   Insert one row per output into `cookbook_recipe_output` instead.
5. **Stop INSERTing into `api_scripts.masked_fields` JSONB**.
   Set `cookbook_recipe_var.is_masked = 1` on the var rows that should be redacted.
6. **Look up `system_id` + `module_id`** from `cookbook_system` /
   `cookbook_module` instead of writing the literal `target_system` /
   `category` strings.
7. **Look up `auth_profile_id`** from `cookbook_auth_profile` instead of
   writing the literal `auth_profile` string.
8. **Optionally set `template_id`** when the recipe was generated from a
   `cookbook_template` row so the engine can re-render on template change.
9. **Set `is_render_card = 1`** (default) for recipes whose result should
   produce an auto-rendered card image; set 0 only when the recipe
   renders its own visualization.
10. **For new subscriptions**, INSERT `cookbook_subscription_access`
    rows granting access -- the new deny-all default means no row = no
    access. System-level grants imply access to every module / recipe /
    trigger under that system.
11. **Use the standardized envelope** in every `run(vars)` return:
    `{status, http_status, data, user_message, system_message}`. The
    kitchen will normalize anything that doesn't match into it, but
    your recipe should produce it natively.

## Concrete worked example

For the `odoo_create_lead` recipe with the new `face_hash` addition, the
end-to-end seed lives in
`hyve-blackbox/hyve-kitchen/seeds/002_cookbook_evolution_seed.sql` --
that file is the canonical reference. Read it side by side with
`Z:\work\claude-cowork\hyve\sample\odoo_create_lead_insert.sql` to see the
column-by-column translation in practice.

## Open questions for the recipe-generating developer

* **Do you want the template renderer (Patch 4 follow-up) written in
  Python (Jinja2) inside the kitchen, or as a separate code-generation
  step outside the runtime?** Inside-kitchen lets the engine re-render
  on template change without a deploy; outside is one less moving part.
  → **DECIDED 2026-05-27: inside-kitchen Jinja2.** See "Template style
  delta" section below for what this means for your pipeline.
* **For multi-step recipes** (e.g. "create_lead then schedule_followup"),
  do you want `is_chainable = 1` recipes to be auto-invoked by the
  engine, or do you want the LLM to explicitly chain them via two
  separate tool calls? The schema supports either; the runtime behaviour
  has not been wired yet (touches deferred items #5 + #13).
  → **DECIDED 2026-05-27: explicit LLM chains for v1.** Auto-chaining
  folds into LLM-driven recipe selection (deferred #13).
* **For the auto-render-card**, what visual style? Today the
  follow-up patch will render a generic title + key-value list. If you
  want per-system theming (Odoo blue, Weather sky-gradient, etc.),
  flag it now so we can add a `cookbook_system.render_theme_json` TEXT
  column before the SDK helper ships.
  → **DECIDED 2026-05-27: no theming in v1; V104 added the column
  anyway** so per-system themes are a one-row update away when you're
  ready. `sdk.render.card` already accepts a `theme={banner_dark,
  banner_light}` dict; cook.py threads it from the recipe's system.

## Post-V104 additions (since this doc was first written)

V104 migration (`004_kitchen_extras.sql`) landed three things relevant
to the recipe generator:

### `cookbook_recipe_var_version` + `cookbook_recipe_output_version` tables

Per-version snapshots of var + output rows. The generator does NOT
write to these directly -- `registry.py::_snapshot_vars_and_outputs`
populates them automatically on every `create_recipe`, `update_recipe`,
`create_recipe_from_template`, and `rerender_recipe_from_template` call.
End result: complete version history (python_body + var schema + output
schema) instead of just python_body.

### `cookbook_system.render_theme_json` column

TEXT column (not JSONB; honours the minimize-JSONB directive). Holds a
small JSON document: `{"banner_dark": "#1565c0", "banner_light":
"#e3f2fd", "text_dark": "#0d47a1", "accent": "#1976d2"}`. NULL means
the SDK uses its built-in status-coloured neutral defaults. To theme a
system: `UPDATE cookbook_system SET render_theme_json = '{"banner_dark":
"#1565c0", ...}' WHERE system_label = 'odoo';` -- no code change.

### `kitchen_invocation.correlation_id` column

Cross-component trace ID. Bridge emits a `correlation_id` when it
publishes events; cookbook `RecipeContext.correlation_id` propagates
it; kitchen persists it here. Lets ops grep one ID across
`bridge_command_audit` -> `kitchen_invocation` -> downstream UE logs.
The generator doesn't have to do anything -- if your recipes want to
emit it in their own log lines, read it from `vars["_correlation_id"]`
(by convention) or from the kitchen request headers when called via
gRPC / REST.

## Runtime endpoints that exist now (didn't when this doc was written)

| Endpoint | Purpose | Status |
|---|---|---|
| `POST /v1/recipes` | Create a recipe with hand-authored `python_body` + schemas | Live |
| `POST /v1/recipes/from_template` | Create a recipe by rendering a `cookbook_template` row against metadata + vars + outputs | Live (V103) |
| `POST /v1/recipes/{id}/rerender` | Re-render an existing template-derived recipe (after `template_text` was edited) | Live (V103) |
| `PATCH /v1/recipes/{id}` | Partial update (display_name, description, python_body, schemas, behaviour flags) | Live |
| `POST /v1/cook` | Execute a recipe; returns the standardized envelope | Live (V103 envelope wrap) |
| `POST /v1/cook/async` | Enqueue async cook with callback URL | Live |
| `DELETE /v1/jobs/{job_id}` | Cancel a queued or in-flight async job | Live (V103) |
| `POST /v1/select` | LLM-driven recipe selection MVP -- keyword + tag scoring filtered by `cookbook_subscription_access` | Live (V103) |
| `GET /v1/tools` | OpenAI-style tool manifest; derived from `cookbook_recipe_var` rows | Live; UNAUTH (gateway pulls without a token) |
| `GET/PATCH /v1/global-vars` | Read/edit `cookbook_global_var` rows; PATCH honours `min_edit_role` via `X-Hyve-User-Role` header | Live (V103) |
| gRPC `Cook` / `CookAsync` / `CancelJob` / `GetJob` / `GetInvocation` / `GetTools` | Same operations over gRPC for hot-path callers | Live on port 50090 |

Auth: when `KITCHEN_JWT_REQUIRED=1` in the kitchen env, every `/v1/*`
route except `/v1/tools` and `/health` requires a `Authorization:
Bearer <token>` header. Mint the token in your generator pipeline with
`kitchen.auth.issue_service_token(subject="recipe-generator",
ttl_seconds=900)`. In dev (the default) the variable is 0 and the
header is optional.

## Template style delta (developer's REPLACE_WITH approach vs landed Jinja2)

This is the most consequential difference for the generator pipeline.
The developer's `template_script_generate_sample_recipe_odoo_create_lead.py`
file uses literal `REPLACE_WITH_X` placeholders intended for sed-style
find-and-replace. The implementation stores templates in
`cookbook_template.template_text` and renders them with Jinja2.

### Side-by-side: same Odoo CREATE template, both styles

**Developer's style** (file with REPLACE_WITH literals):
```python
"""
name:        REPLACE_WITH_NAME
target:      REPLACE_WITH_TARGET
description: REPLACE_WITH_DESCRIPTION
"""

def run(vars: dict) -> dict:
    record = {
        "ODOO_FIELD_NAME": vars.get("YOUR_VAR_NAME", ""),
        # add more fields here
    }
    result = _json_rpc(
        url, "object", "execute_kw",
        db, uid, password,
        "ODOO_MODEL_NAME", "ODOO_METHOD_NAME",
        [record], {},
    )
```

**Landed style** (seeded as `cookbook_template.template_label =
'odoo_crud_create'`):
```python
"""{{ recipe.display_name }}

{{ recipe.description }}

Generated from template odoo_crud_create on {{ now_utc }}.
"""

def run(vars: dict) -> dict:
    record = {
{% for field in recipe.field_mappings %}        "{{ field.api_field }}": vars.get("{{ field.var_name }}", {{ field.default_repr }}),
{% endfor %}    }
    result = _json_rpc(
        url, "object", "execute_kw",
        db, uid, password,
        "{{ recipe.target_model }}", "{{ recipe.target_method }}",
        [record], {},
    )
```

### Five concrete differences

| Aspect | Developer's style | Landed style |
|---|---|---|
| Placeholder syntax | `REPLACE_WITH_X` literals | Jinja2 `{{ var }}` / `{% for ... %}` |
| Storage | One `.py` file per recipe shape | One row in `cookbook_template` per shape; N recipes per template |
| Iteration | Hardcoded field list per template | `{% for field in recipe.field_mappings %}` loop |
| `STANDALONE_VARS` + `__main__` blocks | Kept (dev convenience) | Stripped (engine never reads them) |
| Generation invocation | Read file → sed → write rendered `.py` | `POST /v1/recipes/from_template` with `{template_label, recipe_metadata, vars, outputs}` |

### Two valid migration paths

**Path A (preferred): convert templates to Jinja2 + insert as
`cookbook_template` rows + use `from_template`.** Mechanical rewrite
of placeholders, drop dev-only blocks, drive everything through one
endpoint. Unlocks GUI-managed templates, `POST /{id}/rerender`, full
version history.

**Path B (acceptable for v1): keep the existing pipeline that emits
finished `.py` source via find-and-replace, then POST to
`POST /v1/recipes` (the non-template create endpoint).** Loses
rerender capability but the existing generator stays untouched.
Migrating later is one row in `cookbook_template` + a re-target of
the POST call.

### A worked Path A example

Generating `odoo_create_contact` from the seeded `odoo_crud_create`
template:

```http
POST http://hyve-kitchen:8090/v1/recipes/from_template
Content-Type: application/json
Authorization: Bearer <service-token>    ← only when KITCHEN_JWT_REQUIRED=1

{
    "template_label": "odoo_crud_create",
    "recipe_metadata": {
        "name": "odoo_create_contact",
        "display_name": "Create Odoo Contact",
        "description": "Creates a res.partner record in Odoo CRM.",
        "system_label": "odoo",
        "module_label": "crm",
        "auth_profile_label": "odoo_test",
        "target_model": "res.partner",
        "target_method": "create",
        "primary_output_key": "contact_id",
        "field_mappings": [
            {"api_field": "name",  "var_name": "contact_name",  "default_repr": "\"\""},
            {"api_field": "email", "var_name": "contact_email", "default_repr": "\"\""}
        ]
    },
    "vars": [
        {"var_name": "contact_name",  "is_required": true,  "description": "Full name"},
        {"var_name": "contact_email", "is_required": false, "val_format": "email",
         "description": "Email address"}
    ],
    "outputs": [
        {"output_key": "contact_id", "value_type": "int", "is_required": true,
         "display_label": "Contact ID"}
    ]
}
```

The endpoint renders the template, INSERTs `cookbook_recipe` +
`cookbook_recipe_var` + `cookbook_recipe_var_allowed_value` +
`cookbook_recipe_output` + `cookbook_recipe_version` rows, snapshots
to `cookbook_recipe_var_version` + `cookbook_recipe_output_version`
(V104), and returns the synthesized recipe. All in one transaction.

### One more gotcha: subscription access

Under the V103 deny-by-default `cookbook_subscription_access` model, a
new subscription gets ZERO recipe access until the generator inserts at
least one allow row. After creating a recipe, if you want the
`kiosk-fleet` subscription to be able to call it:

```sql
INSERT INTO cookbook_subscription_access (
    subscription_id, recipe_id, access_action, reason, created_by
) VALUES (
    (SELECT id FROM subscription WHERE subscription_name = 'kiosk-fleet'),
    (SELECT id FROM cookbook_recipe WHERE name = 'odoo_create_contact'),
    'allow',
    'recipe-generator initial grant',
    'recipe-generator'
);
```

Or grant at the system level (which lets the subscription call every
recipe under that system):

```sql
INSERT INTO cookbook_subscription_access (
    subscription_id, system_id, access_action, reason, created_by
) VALUES (
    (SELECT id FROM subscription WHERE subscription_name = 'kiosk-fleet'),
    (SELECT id FROM cookbook_system WHERE system_label = 'odoo'),
    'allow',
    'kiosk-fleet allowed to use all Odoo recipes',
    'recipe-generator'
);
```

The seed file already does the latter for the existing subscriptions,
so you only need this for newly-created subscriptions OR for recipes
that should bypass the system-level grant with a per-recipe deny.
