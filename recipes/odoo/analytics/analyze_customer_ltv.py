"""Tier 4: analyze_customer_ltv — annualized LTV from transaction history and loyalty."""

from __future__ import annotations

from typing import Any, Dict

from recipes._cdm.envelope import success
from recipes.odoo.analytics._recipe import tier4_recipe
from recipes.odoo.analytics._tier4_base import (
    delta_pct,
    dominant_currency,
    trend_from_delta,
    window_totals,
)

RECIPE_NAME = "analyze_customer_ltv"


def _analyze(resolved: Dict[str, Any]) -> Dict[str, Any]:
    transactions = resolved["CommonTransaction"]
    recent_total, prior_total, count = window_totals(transactions, recent_days=365, prior_days=365)
    points = resolved["CommonLoyaltyStatus"].get("points_balance") or 0
    confidence = min(0.95, 0.5 + min(count, 20) * 0.02 + (0.1 if points > 500 else 0))
    pct = delta_pct(recent_total, prior_total)
    return success(
        {
            "annualized_ltv": round(recent_total, 2),
            "currency": dominant_currency(transactions),
            "trend": trend_from_delta(pct),
            "confidence": round(confidence, 2),
        }
    )


run = tier4_recipe(RECIPE_NAME, _analyze, error_message="LTV analysis failed.")
