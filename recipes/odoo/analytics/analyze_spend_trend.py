"""Tier 4: analyze_spend_trend — weekly spend buckets and prior-period delta."""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime
from typing import Any, Dict, List

from recipes._cdm.envelope import success
from recipes.odoo.analytics._recipe import tier4_recipe
from recipes.odoo.analytics._tier4_base import (
    delta_pct,
    iter_transactions,
    parse_iso_date,
    period_totals,
    trend_from_delta,
    tx_amount,
)

RECIPE_NAME = "analyze_spend_trend"
_EMPTY = {
    "period": "weekly",
    "buckets": [],
    "total_current": 0.0,
    "total_prior": 0.0,
    "delta_pct": 0.0,
    "trend": "flat",
}


def _week_key(dt: datetime) -> str:
    iso = dt.isocalendar()
    return f"{iso.year}-W{iso.week:02d}"


def _weekly_buckets(transactions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    buckets: Dict[str, float] = defaultdict(float)
    for tx in iter_transactions(transactions):
        if dt := parse_iso_date(tx.get("date")):
            buckets[_week_key(dt)] += tx_amount(tx)
    return [{"week": week, "total": round(amount, 2)} for week, amount in sorted(buckets.items())]


def _analyze(resolved: Dict[str, Any]) -> Dict[str, Any]:
    transactions = resolved["CommonTransaction"]
    if not transactions:
        return success(_EMPTY, user_message="No transactions to analyze.")

    total_current, total_prior = period_totals(transactions)
    pct = delta_pct(total_current, total_prior)
    return success(
        {
            "period": "weekly",
            "buckets": _weekly_buckets(transactions),
            "total_current": round(total_current, 2),
            "total_prior": round(total_prior, 2),
            "delta_pct": pct,
            "trend": trend_from_delta(pct),
        }
    )


run = tier4_recipe(RECIPE_NAME, _analyze, error_message="Spend trend analysis failed.")
