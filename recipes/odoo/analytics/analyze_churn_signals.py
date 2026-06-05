"""Tier 4: analyze_churn_signals — churn score from profile, transactions, and tickets."""

from __future__ import annotations

from typing import Any, Dict, List

from recipes._cdm.envelope import success
from recipes.odoo.analytics._recipe import tier4_recipe
from recipes.odoo.analytics._tier4_base import (
    OPEN_TICKET_STATUSES,
    accumulate_scores,
    filter_by_status,
    last_paid_transaction_date,
    normalize_status,
    parse_iso_date,
    utc_now,
)

RECIPE_NAME = "analyze_churn_signals"


def _risk_level(score: int) -> str:
    if score >= 60:
        return "high"
    if score >= 35:
        return "medium"
    return "low"


def _score_from_recency(last_seen_at: str | None) -> tuple[int, List[str]]:
    last_seen = parse_iso_date(last_seen_at or "")
    if not last_seen:
        return 15, ["missing_last_seen_at"]
    days_idle = (utc_now() - last_seen).days
    if days_idle > 180:
        return 40, ["last_seen_over_180_days"]
    if days_idle > 90:
        return 25, ["last_seen_over_90_days"]
    return 0, []


def _score_from_transactions(transactions: List[Dict[str, Any]]) -> tuple[int, List[str]]:
    last_paid = last_paid_transaction_date(transactions)
    if not last_paid:
        return 20, ["no_paid_transactions"]
    gap_days = (utc_now() - last_paid).days
    if gap_days > 120:
        return 30, ["last_purchase_over_120_days"]
    if gap_days > 60:
        return 15, ["purchase_gap_increased"]
    return 0, []


def _score_from_tickets(tickets: List[Dict[str, Any]]) -> tuple[int, List[str]]:
    open_tickets = filter_by_status(tickets, OPEN_TICKET_STATUSES)
    if not open_tickets:
        return 0, []
    factors = ["open_service_tickets"]
    score = min(25, 10 + len(open_tickets) * 5)
    if any(normalize_status(t.get("priority")) in ("high", "urgent") for t in open_tickets):
        factors.append("open_complaint_ticket")
    if any(normalize_status(t.get("priority")) == "urgent" for t in open_tickets):
        score += 10
        factors.append("urgent_open_ticket")
    return score, factors


def _analyze(resolved: Dict[str, Any]) -> Dict[str, Any]:
    score, risk_factors = accumulate_scores(
        lambda: _score_from_recency(resolved["CommonCustomerProfile"].get("last_seen_at")),
        lambda: _score_from_transactions(resolved["CommonTransaction"]),
        lambda: _score_from_tickets(resolved["CommonServiceTicket"]),
    )
    score = min(100, score)
    return success(
        {
            "score": score,
            "risk_level": _risk_level(score),
            "risk_factors": risk_factors,
        }
    )


run = tier4_recipe(RECIPE_NAME, _analyze, error_message="Churn analysis failed.")
