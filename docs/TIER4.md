# Tier 4 — usage & contracts

Tier 4 recipes are **deterministic analytics**: normalized CDM in → KPI dict out. No LLM and no Odoo/API calls inside these scripts.

**Canonical field definitions:** `config/outputs/*.yaml` and `config/outputs/GapReportItem.yaml`  
**Var keys for `run(vars)`:** `config/tier4_var_mapping.json`  
**Phase 2 platform docs:** [analytics_recipe_author_guide.txt](../analytics_recipe_author_guide.txt), [hyve_phase2_brainstorm_v2.txt](../hyve_phase2_brainstorm_v2.txt)

This file documents **what this repo implements**, aligned with those docs.

---

## Response envelope (all recipes)

Every `run(vars)` returns:

```json
{
  "status": "SUCCESS",
  "http_status": 200,
  "data": { },
  "user_message": "...",
  "system_message": "..."
}
```

On failure, `status` is `MISSING_INPUT`, `VALIDATION_ERROR`, or `UNKNOWN_ERROR` and `data` is `{}`.

---

## Recipe index

| Recipe | CDM inputs | `run(vars)` keys | Output type | Upstream Tier 3.5 (planned) |
|--------|------------|------------------|-------------|----------------------------|
| `analyze_spend_trend` | `CommonTransaction[]` | `transactions` | `SpendTrend` | `normalize_transaction_history` |
| `analyze_inventory_gaps` | `CommonInventorySnapshot[]`, `CommonTransaction[]` | `inventory_snapshots`, `transactions` | `GapReport` | `normalize_inventory_snapshot`, `normalize_transaction_history` |
| `analyze_churn_signals` | `CommonCustomerProfile`, `CommonTransaction[]`, `CommonServiceTicket[]` | `customer_profile`, `transactions`, `service_tickets` | `ChurnScore` | `normalize_customer_profile`, `normalize_transaction_history`, `normalize_helpdesk_tickets` |
| `analyze_customer_ltv` | `CommonTransaction[]`, `CommonLoyaltyStatus` | `transactions`, `loyalty_status` | `LTVProjection` | `normalize_transaction_history`, `normalize_loyalty_status` |
| `analyze_customer_segment` | `CommonTransaction[]` | `transactions` | `SegmentProfile` | `normalize_transaction_history` |
| `analyze_store_session_metrics` | `CommonKioskSession[]` | `kiosk_sessions` | `SessionMetrics` | `normalize_kiosk_session` |

Cookbook metadata when V105 is applied: `tier=tier4`, `cache_scope=tenant`, `cache_ttl_seconds=120` — see `samples/tier4/v105_metadata.sql`.

---

## Output contracts (`result["data"]`)

### SpendTrend — `analyze_spend_trend`

**Meaning (per author guide):** weekly aggregations and delta vs the prior 28-day window.

| Field | Type | Notes |
|-------|------|--------|
| `period` | string | `"weekly"` (monthly buckets not implemented yet) |
| `buckets` | list | `{ "week": "2026-W20", "total": number }` |
| `total_current` | float | Sum in last 28 days |
| `total_prior` | float | Sum in prior 28 days |
| `delta_pct` | float | Percent change vs prior window |
| `trend` | string | `up` \| `down` \| `flat` (±5% threshold) |

```json
{
  "period": "weekly",
  "buckets": [{ "week": "2026-W20", "total": 120.5 }],
  "total_current": 205.5,
  "total_prior": 150.0,
  "delta_pct": 37.0,
  "trend": "up"
}
```

### GapReport — `analyze_inventory_gaps`

**Meaning:** sales velocity from transactions + days-to-stockout per inventory snapshot.

| Field | Type | Notes |
|-------|------|--------|
| `as_of` | string | ISO-8601 UTC timestamp |
| `gaps` | list | See **GapReportItem** below |

**GapReportItem** (each element of `gaps`):

| Field | Type | Notes |
|-------|------|--------|
| `product_id` | string | |
| `location_name` | string | optional |
| `qty_available` | float | |
| `sales_velocity_per_day` | float | Units/day over 90-day lookback |
| `days_to_stockout` | float \| null | `null` if velocity is 0 |
| `severity` | string | `critical` \| `warning` \| `ok` |

```json
{
  "as_of": "2026-06-04T12:00:00Z",
  "gaps": [{
    "product_id": "PROD-B",
    "location_name": "Main Warehouse",
    "qty_available": 3.0,
    "sales_velocity_per_day": 0.15,
    "days_to_stockout": 20.0,
    "severity": "warning"
  }]
}
```

### ChurnScore — `analyze_churn_signals`

**Meaning:** score 0–100 from profile recency, purchase gap, and open tickets (author guide).

| Field | Type | Notes |
|-------|------|--------|
| `score` | int | 0–100, capped |
| `risk_level` | string | `high` (≥60) \| `medium` (≥35) \| `low` |
| `risk_factors` | list[string] | Stable codes, not prose |

**`risk_factors` codes:**

| Code | When |
|------|------|
| `missing_last_seen_at` | Profile has no `last_seen_at` |
| `last_seen_over_180_days` | Idle > 180 days |
| `last_seen_over_90_days` | Idle > 90 days |
| `no_paid_transactions` | No paid/confirmed transactions |
| `last_purchase_over_120_days` | Last paid tx > 120 days ago |
| `purchase_gap_increased` | Last paid tx > 60 days ago |
| `open_service_tickets` | One or more open tickets |
| `open_complaint_ticket` | Open ticket with high/urgent priority |
| `urgent_open_ticket` | Open urgent ticket (+extra score) |

```json
{
  "score": 82,
  "risk_level": "high",
  "risk_factors": ["last_seen_over_90_days", "open_service_tickets"]
}
```

### LTVProjection — `analyze_customer_ltv`

**Meaning:** annualized spend (last 365 days) and trend vs prior year (author guide: annualized + trend).

| Field | Type | Notes |
|-------|------|--------|
| `annualized_ltv` | float | Sum of non-cancelled tx in last 365 days |
| `currency` | string | ISO 4217 from transactions, default `USD` |
| `trend` | string | `up` \| `down` \| `flat` vs prior 365-day window |
| `confidence` | float | 0–1 heuristic from tx count + loyalty points |

```json
{
  "annualized_ltv": 405.5,
  "currency": "USD",
  "trend": "up",
  "confidence": 0.72
}
```

### SegmentProfile — `analyze_customer_segment`

**Meaning:** heuristic segment from transaction history (brainstorm: cohort / product affinity).

| Field | Type | Notes |
|-------|------|--------|
| `segment_label` | string | `high_value` \| `mid_value` \| `value_shopper` \| `no_activity` |
| `avg_order_value` | float | |
| `top_products` | list | `{ "product_id", "qty" }` top 5 |
| `order_count` | int | Non-cancelled transactions |

### SessionMetrics — `analyze_store_session_metrics`

**Meaning:** store-level kiosk session aggregates (brainstorm: volume, conversion, intents).

| Field | Type | Notes |
|-------|------|--------|
| `session_count` | int | |
| `conversion_rate` | float | 0–1 |
| `top_intents` | list | `{ "intent", "count" }` top 5 |
| `avg_duration_seconds` | float | Omitted from average when no durations |

---

## Quick start

```bash
python -m unittest tests.test_cdm_config tests.test_tier4_analyzers -v
python -m tests.run_tier4_analytics
```

```python
from recipes._cdm.loader import load_fixture
from recipes.odoo.analytics.analyze_spend_trend import run

print(run({"transactions": load_fixture("transactions_90d.json")})["data"])
```

All recipes via registry:

```python
from recipes.odoo.analytics._registry import RUNNERS, vars_from_fixtures

for name in RUNNERS:
    print(name, RUNNERS[name](vars_from_fixtures(name))["status"])
```

Test fixture paths: `config/tier4_test_fixtures.json`.

---

## Inventory what-if (demo)

Pass a modified snapshot list (Tier 5 `simulate_inventory_change` not required for local tests):

```python
from recipes._cdm.loader import load_fixture
from recipes.odoo.analytics.analyze_inventory_gaps import run

baseline = run({
    "transactions": load_fixture("transactions_90d.json"),
    "inventory_snapshots": load_fixture("inventory_snapshot.json"),
})
# Re-run with adjusted snapshots to simulate +20 units on hand, etc.
```

June 13 demo chain (brainstorm): `normalize_inventory_snapshot` → `normalize_transaction_history` → `analyze_inventory_gaps` → `simulate_inventory_change` (T5) → `analyze_inventory_gaps` again.

---

## Cookbook SQL

```bash
psql ... -f samples/tier4/00_scaffold_odoo.sql
psql ... -f samples/tier4/analyze_<name>_insert.sql   # each analyzer
python scripts/render_tier4_sql.py                     # regenerate from .py
psql ... -f samples/tier4/v105_metadata.sql            # after V105 migration
psql ... -f samples/tier4/v105_dependencies.sql
```

---

## Changing contracts

1. Edit `config/outputs/*.yaml` (and `config/cdm/*.yaml` for inputs).
2. Update `config/cdm_manifest.json` if adding types.
3. Implement in `recipes/odoo/analytics/analyze_*.py`.
4. Update `tests/fixtures/cdm/` and run unit tests.
5. Run `python scripts/render_tier4_sql.py`.

---

## Alignment notes (Phase 2 docs vs this repo)

| Topic | Phase 2 docs | This repo |
|-------|----------------|-----------|
| Tier 4 role | CDM-only, `analyze_*`, no source APIs | Matches |
| `analyze_spend_trend` inputs | Author guide: `CommonTransaction` only | Matches (brainstorm diagram sometimes shows profile; not required here) |
| SpendTrend period | Weekly/monthly mentioned | **Weekly** buckets + 28d/current-prior totals; monthly not yet |
| All six analyzers | Listed in brainstorm | **All six** implemented in Python |
| `analyze_spend_trend.sql` sample | Author guide points at hyve-blackbox | Logic lives here under `recipes/odoo/analytics/` |
| Production chains | Redis + `/v1/cook` in blackbox | Local tests use fixtures; no Redis in this package |
