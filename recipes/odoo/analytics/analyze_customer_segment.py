"""Tier 4: analyze_customer_segment — heuristic cohort summary from transactions."""

from __future__ import annotations

from typing import Any, Dict

from recipes._cdm.envelope import success
from recipes.odoo.analytics._recipe import tier4_recipe
from recipes.odoo.analytics._tier4_base import (
    iter_transactions,
    sum_line_item_qty_by_product,
    top_k_items,
    tx_amount,
)

RECIPE_NAME = "analyze_customer_segment"
_EMPTY = {
    "segment_label": "no_activity",
    "avg_order_value": 0.0,
    "top_products": [],
    "order_count": 0,
}


def _segment_label(avg_order_value: float) -> str:
    if avg_order_value >= 500:
        return "high_value"
    if avg_order_value >= 150:
        return "mid_value"
    return "value_shopper"


def _analyze(resolved: Dict[str, Any]) -> Dict[str, Any]:
    active = list(iter_transactions(resolved["CommonTransaction"]))
    if not active:
        return success(_EMPTY, user_message="No transactions for segmentation.")

    totals = [tx_amount(tx) for tx in active]
    order_count = len(totals)
    avg_order_value = round(sum(totals) / order_count, 2)
    return success(
        {
            "segment_label": _segment_label(avg_order_value),
            "avg_order_value": avg_order_value,
            "top_products": top_k_items(sum_line_item_qty_by_product(active)),
            "order_count": order_count,
        }
    )


run = tier4_recipe(RECIPE_NAME, _analyze, error_message="Segment analysis failed.")
