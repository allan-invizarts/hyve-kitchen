"""Tier 4: analyze_inventory_gaps — stockout risk from snapshots and transaction velocity."""

from __future__ import annotations

from datetime import timedelta
from typing import Any, Dict, List

from recipes._cdm.envelope import success
from recipes.odoo.analytics._recipe import tier4_recipe
from recipes.odoo.analytics._tier4_base import (
    iso_timestamp_z,
    iter_transactions,
    sum_line_item_qty_by_product,
    utc_now,
)

RECIPE_NAME = "analyze_inventory_gaps"
LOOKBACK_DAYS = 90
_SEVERITY_ORDER = {"critical": 0, "warning": 1, "ok": 2}


def _daily_velocity(transactions: List[Dict[str, Any]]) -> Dict[str, float]:
    cutoff = utc_now() - timedelta(days=LOOKBACK_DAYS)
    qty_by_product = sum_line_item_qty_by_product(list(iter_transactions(transactions, since=cutoff)))
    return {pid: qty / LOOKBACK_DAYS for pid, qty in qty_by_product.items()}


def _severity(
    days_to_stockout: float | None,
    qty_available: float,
    reorder_point: float | None,
) -> str:
    if days_to_stockout is None:
        return "ok"
    if reorder_point is not None and qty_available <= reorder_point:
        return "critical"
    if days_to_stockout <= 7:
        return "critical"
    if days_to_stockout <= 14:
        return "warning"
    return "ok"


def _gap_row(snap: Dict[str, Any], velocity: Dict[str, float]) -> Dict[str, Any]:
    product_id = str(snap.get("product_id", ""))
    qty_available = float(snap.get("qty_available") or 0)
    daily = velocity.get(product_id, 0.0)
    reorder = snap.get("reorder_point")
    reorder_f = float(reorder) if reorder is not None else None
    days_to_stockout = round(qty_available / daily, 1) if daily > 0 else None
    return {
        "product_id": product_id,
        "location_name": snap.get("location_name"),
        "qty_available": qty_available,
        "sales_velocity_per_day": round(daily, 4),
        "days_to_stockout": days_to_stockout,
        "severity": _severity(days_to_stockout, qty_available, reorder_f),
    }


def _analyze(resolved: Dict[str, Any]) -> Dict[str, Any]:
    velocity = _daily_velocity(resolved["CommonTransaction"])
    gaps = [_gap_row(snap, velocity) for snap in resolved["CommonInventorySnapshot"]]
    gaps.sort(
        key=lambda g: (
            _SEVERITY_ORDER.get(g["severity"], 9),
            g["days_to_stockout"] if g["days_to_stockout"] is not None else 9999,
        )
    )
    return success({"as_of": iso_timestamp_z(), "gaps": gaps})


run = tier4_recipe(RECIPE_NAME, _analyze, error_message="Inventory gap analysis failed.")
