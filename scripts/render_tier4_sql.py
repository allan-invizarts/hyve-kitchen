#!/usr/bin/env python3
"""Generate idempotent cookbook INSERT SQL for Tier 4 recipes from Python sources."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANALYTICS = ROOT / "recipes" / "odoo" / "analytics"
OUT_DIR = ROOT / "samples" / "tier4"
VAR_MAPPING = ROOT / "config" / "tier4_var_mapping.json"

RECIPES = [
    {
        "name": "analyze_spend_trend",
        "display_name": "Analyze Spend Trend",
        "description": "Tier 4: weekly spend buckets and prior-period delta from CommonTransaction.",
        "cdm_output_type": "SpendTrend",
        "cdm_input_types_csv": "CommonTransaction",
        "cache_ttl_seconds": 120,
        "dependencies": ["normalize_transaction_history"],
        "outputs": [
            ("spend_trend", "data", "object", 1, "SpendTrend analysis result", "Spend Trend", 10),
        ],
    },
    {
        "name": "analyze_inventory_gaps",
        "display_name": "Analyze Inventory Gaps",
        "description": "Tier 4: stockout risk from inventory snapshots and transaction velocity.",
        "cdm_output_type": "GapReport",
        "cdm_input_types_csv": "CommonInventorySnapshot,CommonTransaction",
        "cache_ttl_seconds": 120,
        "dependencies": ["normalize_transaction_history", "normalize_inventory_snapshot"],
        "outputs": [
            ("gap_report", "data", "object", 1, "GapReport with per-product risk", "Gap Report", 10),
        ],
    },
    {
        "name": "analyze_churn_signals",
        "display_name": "Analyze Churn Signals",
        "description": "Tier 4: churn score from profile, transactions, and open tickets.",
        "cdm_output_type": "ChurnScore",
        "cdm_input_types_csv": "CommonCustomerProfile,CommonTransaction,CommonServiceTicket",
        "cache_ttl_seconds": 120,
        "dependencies": [
            "normalize_customer_profile",
            "normalize_transaction_history",
            "normalize_helpdesk_tickets",
        ],
        "outputs": [
            ("churn_score", "data", "object", 1, "ChurnScore result", "Churn Score", 10),
        ],
    },
    {
        "name": "analyze_customer_ltv",
        "display_name": "Analyze Customer LTV",
        "description": "Tier 4: annualized LTV projection from transactions and loyalty.",
        "cdm_output_type": "LTVProjection",
        "cdm_input_types_csv": "CommonTransaction,CommonLoyaltyStatus",
        "cache_ttl_seconds": 120,
        "dependencies": ["normalize_transaction_history", "normalize_loyalty_status"],
        "outputs": [
            ("ltv_projection", "data", "object", 1, "LTVProjection result", "LTV Projection", 10),
        ],
    },
    {
        "name": "analyze_customer_segment",
        "display_name": "Analyze Customer Segment",
        "description": "Tier 4: heuristic segment profile from transaction history.",
        "cdm_output_type": "SegmentProfile",
        "cdm_input_types_csv": "CommonTransaction",
        "cache_ttl_seconds": 120,
        "dependencies": ["normalize_transaction_history"],
        "outputs": [
            ("segment_profile", "data", "object", 1, "SegmentProfile result", "Segment", 10),
        ],
    },
    {
        "name": "analyze_store_session_metrics",
        "display_name": "Analyze Store Session Metrics",
        "description": "Tier 4: aggregate kiosk session metrics.",
        "cdm_output_type": "SessionMetrics",
        "cdm_input_types_csv": "CommonKioskSession",
        "cache_ttl_seconds": 120,
        "dependencies": ["normalize_kiosk_session"],
        "outputs": [
            ("session_metrics", "data", "object", 1, "SessionMetrics result", "Session Metrics", 10),
        ],
    },
]


def _escape_sql_dollar(body: str) -> str:
    return body.replace("$", "$$")


def _load_var_mapping() -> dict:
    return json.loads(VAR_MAPPING.read_text(encoding="utf-8"))


def _var_description(type_name: str) -> str:
    object_types = {"CommonCustomerProfile", "CommonLoyaltyStatus"}
    shape = "object" if type_name in object_types else "array"
    return f"{type_name} JSON {shape}"


def _vars_for_recipe(spec: dict, var_mapping: dict) -> list[tuple[str, str, int, str, int]]:
    inputs = (var_mapping.get(spec["name"]) or {}).get("inputs")
    if not inputs:
        raise KeyError(f"No tier4 var mapping for recipe: {spec['name']}")
    return [
        (var_name, "string", 0, _var_description(type_name), index * 10)
        for index, (type_name, var_name) in enumerate(inputs.items(), start=1)
    ]


def render_recipe_sql(spec: dict, var_mapping: dict) -> str:
    py_path = ANALYTICS / f"{spec['name']}.py"
    body = py_path.read_text(encoding="utf-8")
    body_sql = _escape_sql_dollar(body)
    recipe_vars = _vars_for_recipe(spec, var_mapping)

    var_rows = ",\n".join(
        f"    ('{v[0]}', '{v[1]}', {v[2]}, '{v[3]}', {v[4]})"
        for v in recipe_vars
    )
    out_rows = ",\n".join(
        f"    ('{o[0]}', '{o[2]}', {o[3]}, '{o[4]}', '{o[5]}', {o[6]})"
        for o in spec["outputs"]
    )

    return f"""-- Tier 4 recipe: {spec["name"]} (generated by scripts/render_tier4_sql.py)
-- Requires migrations 001-004 applied. V105 tier/cdm columns: see v105_metadata.sql
-- Re-run: python scripts/render_tier4_sql.py

BEGIN;

INSERT INTO cookbook_recipe (
    name, display_name, description,
    system_id, module_id, auth_profile_id,
    python_body, entrypoint,
    timeout_seconds, memory_mb,
    is_enabled, is_internal, required_role,
    is_read_only, is_getset, is_batch, is_chainable, is_render_card,
    expected_duration_ms, created_by
)
SELECT
    '{spec["name"]}',
    '{spec["display_name"]}',
    '{spec["description"]}',
    (SELECT id FROM cookbook_system WHERE system_label = 'odoo'),
    (SELECT id FROM cookbook_module WHERE module_label = 'analytics' AND system_id = (SELECT id FROM cookbook_system WHERE system_label = 'odoo')),
    (SELECT id FROM cookbook_auth_profile WHERE profile_label = 'odoo_test'),
    $PY$
{body_sql}
$PY$,
    'run',
    30, 128,
    1, 0, 'user',
    1, 0, 0, 1, 1,
    500, 'tier4-generator'
WHERE NOT EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = '{spec["name"]}');

INSERT INTO cookbook_recipe_var (recipe_id, var_name, var_type, is_required, description, sort_order, created_by)
SELECT r.id, v.var_name, v.var_type, v.is_required, v.description, v.sort_order, 'tier4-generator'
FROM cookbook_recipe r
CROSS JOIN (VALUES
{var_rows}
) AS v(var_name, var_type, is_required, description, sort_order)
WHERE r.name = '{spec["name"]}'
ON CONFLICT (recipe_id, var_name) DO NOTHING;

INSERT INTO cookbook_recipe_output (recipe_id, output_key, source_path, value_type, is_required, description, display_label, sort_order, created_by)
SELECT r.id, o.output_key, 'data', o.value_type, o.is_required, o.description, o.display_label, o.sort_order, 'tier4-generator'
FROM cookbook_recipe r
CROSS JOIN (VALUES
{out_rows}
) AS o(output_key, _src, value_type, is_required, description, display_label, sort_order)
WHERE r.name = '{spec["name"]}'
ON CONFLICT (recipe_id, output_key) DO NOTHING;

COMMIT;
"""


def render_dependencies_sql() -> str:
    lines = [
        "-- cookbook_recipe_dependency rows (requires V105 table from hyve-blackbox PR-1)",
        "BEGIN;",
        "",
    ]
    for spec in RECIPES:
        for dep in spec["dependencies"]:
            lines.append(
                f"""INSERT INTO cookbook_recipe_dependency (id, recipe_id, depends_on_recipe_id, dependency_type, created_by)
SELECT generate_custom_guid('DEP'),
       (SELECT id FROM cookbook_recipe WHERE name = '{spec["name"]}'),
       (SELECT id FROM cookbook_recipe WHERE name = '{dep}'),
       'data', 'tier4-generator'
WHERE EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = '{spec["name"]}')
  AND EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = '{dep}')
  AND NOT EXISTS (
      SELECT 1 FROM cookbook_recipe_dependency d
      JOIN cookbook_recipe r ON r.id = d.recipe_id
      JOIN cookbook_recipe u ON u.id = d.depends_on_recipe_id
      WHERE r.name = '{spec["name"]}' AND u.name = '{dep}'
  );"""
            )
            lines.append("")
    lines.append("COMMIT;")
    return "\n".join(lines)


def main():
    var_mapping = _load_var_mapping()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for spec in RECIPES:
        out = OUT_DIR / f"{spec['name']}_insert.sql"
        out.write_text(render_recipe_sql(spec, var_mapping), encoding="utf-8")
        print(f"Wrote {out}")
    meta = OUT_DIR / "v105_metadata.sql"
    meta.write_text(V105_METADATA, encoding="utf-8")
    print(f"Wrote {meta}")
    deps = OUT_DIR / "v105_dependencies.sql"
    deps.write_text(render_dependencies_sql(), encoding="utf-8")
    print(f"Wrote {deps}")


V105_METADATA = """-- V105 Phase 2 metadata for Tier 4 recipes (apply AFTER hyve-blackbox PR-1 migration)
-- Updates cookbook_recipe rows seeded by *_insert.sql files in this directory.
-- Safe to re-run when columns exist.

BEGIN;

UPDATE cookbook_recipe SET
    tier = 'tier4',
    cache_scope = 'tenant',
    is_read_only = 1,
    is_chainable = 1
WHERE name IN (
    'analyze_spend_trend',
    'analyze_inventory_gaps',
    'analyze_churn_signals',
    'analyze_customer_ltv',
    'analyze_customer_segment',
    'analyze_store_session_metrics'
);

UPDATE cookbook_recipe SET cdm_output_type = 'SpendTrend', cdm_input_types_csv = 'CommonTransaction', cache_ttl_seconds = 120
WHERE name = 'analyze_spend_trend';

UPDATE cookbook_recipe SET cdm_output_type = 'GapReport', cdm_input_types_csv = 'CommonInventorySnapshot,CommonTransaction', cache_ttl_seconds = 120
WHERE name = 'analyze_inventory_gaps';

UPDATE cookbook_recipe SET cdm_output_type = 'ChurnScore', cdm_input_types_csv = 'CommonCustomerProfile,CommonTransaction,CommonServiceTicket', cache_ttl_seconds = 120
WHERE name = 'analyze_churn_signals';

UPDATE cookbook_recipe SET cdm_output_type = 'LTVProjection', cdm_input_types_csv = 'CommonTransaction,CommonLoyaltyStatus', cache_ttl_seconds = 120
WHERE name = 'analyze_customer_ltv';

UPDATE cookbook_recipe SET cdm_output_type = 'SegmentProfile', cdm_input_types_csv = 'CommonTransaction', cache_ttl_seconds = 120
WHERE name = 'analyze_customer_segment';

UPDATE cookbook_recipe SET cdm_output_type = 'SessionMetrics', cdm_input_types_csv = 'CommonKioskSession', cache_ttl_seconds = 120
WHERE name = 'analyze_store_session_metrics';

COMMIT;
"""

if __name__ == "__main__":
    main()
