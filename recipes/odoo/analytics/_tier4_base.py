"""Shared helpers for Tier 4 analyzers."""

from __future__ import annotations

from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, Iterable, List, Optional, Tuple

from recipes._cdm.envelope import error, success
from recipes._cdm.loader import recipe_input_types, resolve_tier4_inputs
from recipes._cdm.validation import validate_cdm

CANCELLED_STATUS = "cancelled"
PAID_STATUSES = frozenset({"paid", "confirmed", "done"})
OPEN_TICKET_STATUSES = frozenset({"open", "in_progress", "new"})


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso_timestamp_z(when: Optional[datetime] = None) -> str:
    return (when or utc_now()).isoformat().replace("+00:00", "Z")


def parse_iso_date(value: Any) -> Optional[datetime]:
    if not value or not isinstance(value, str):
        return None
    try:
        dt = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def normalize_status(value: Any) -> str:
    return (value or "").lower() if isinstance(value, str) else ""


def tx_status(tx: Dict[str, Any]) -> str:
    return normalize_status(tx.get("status"))


def is_cancelled(tx: Dict[str, Any]) -> bool:
    return tx_status(tx) == CANCELLED_STATUS


def is_paid(tx: Dict[str, Any]) -> bool:
    return tx_status(tx) in PAID_STATUSES


def tx_amount(tx: Dict[str, Any]) -> float:
    return float(tx.get("total_amount") or 0)


def dominant_currency(transactions: List[Dict[str, Any]], default: str = "USD") -> str:
    counts: Dict[str, int] = defaultdict(int)
    for tx in transactions:
        currency = tx.get("currency")
        if isinstance(currency, str) and currency.strip():
            counts[currency.strip().upper()] += 1
    if not counts:
        return default
    return max(counts, key=counts.get)


def iter_transactions(
    transactions: List[Dict[str, Any]],
    *,
    exclude_cancelled: bool = True,
    since: Optional[datetime] = None,
    until: Optional[datetime] = None,
) -> Iterable[Dict[str, Any]]:
    for tx in transactions:
        if exclude_cancelled and is_cancelled(tx):
            continue
        dt = parse_iso_date(tx.get("date"))
        if since and (not dt or dt < since):
            continue
        if until and (not dt or dt >= until):
            continue
        yield tx


def filter_by_status(items: List[Dict[str, Any]], allowed: frozenset[str]) -> List[Dict[str, Any]]:
    return [item for item in items if normalize_status(item.get("status")) in allowed]


def sum_line_item_qty_by_product(transactions: List[Dict[str, Any]]) -> Dict[str, float]:
    totals: Dict[str, float] = defaultdict(float)
    for tx in transactions:
        for item in tx.get("items") or []:
            if isinstance(item, dict) and item.get("product_id"):
                totals[str(item["product_id"])] += float(item.get("qty") or 0)
    return dict(totals)


def top_k_items(
    totals: Dict[str, float],
    *,
    limit: int = 5,
    id_key: str = "product_id",
    value_key: str = "qty",
) -> List[Dict[str, Any]]:
    return [
        {id_key: key, value_key: round(qty, 2)}
        for key, qty in sorted(totals.items(), key=lambda item: -item[1])[:limit]
    ]


def window_totals(
    transactions: List[Dict[str, Any]],
    *,
    recent_days: int,
    prior_days: int,
) -> Tuple[float, float, int]:
    now = utc_now()
    recent_start = now - timedelta(days=recent_days)
    prior_start = recent_start - timedelta(days=prior_days)
    recent_total = prior_total = 0.0
    count = 0
    for tx in iter_transactions(transactions):
        dt = parse_iso_date(tx.get("date"))
        if not dt:
            continue
        count += 1
        amount = tx_amount(tx)
        if dt >= recent_start:
            recent_total += amount
        elif dt >= prior_start:
            prior_total += amount
    return recent_total, prior_total, count


def period_totals(
    transactions: List[Dict[str, Any]],
    *,
    current_days: int = 28,
    prior_days: int = 28,
) -> Tuple[float, float]:
    recent, prior, _ = window_totals(transactions, recent_days=current_days, prior_days=prior_days)
    return recent, prior


def delta_pct(current: float, prior: float) -> float:
    if prior > 0:
        return round(((current - prior) / prior) * 100.0, 2)
    return 100.0 if current > 0 else 0.0


def trend_from_delta(delta: float, threshold: float = 5.0) -> str:
    if delta > threshold:
        return "up"
    if delta < -threshold:
        return "down"
    return "flat"


def last_paid_transaction_date(transactions: List[Dict[str, Any]]) -> Optional[datetime]:
    dates = [
        dt
        for tx in transactions
        if is_paid(tx) and (dt := parse_iso_date(tx.get("date"))) is not None
    ]
    return max(dates) if dates else None


def accumulate_scores(
    *scorers: Callable[[], Tuple[int, List[str]]],
) -> Tuple[int, List[str]]:
    score = 0
    factors: List[str] = []
    for scorer in scorers:
        partial, partial_factors = scorer()
        score += partial
        factors.extend(partial_factors)
    return score, factors


def load_tier4_inputs(
    recipe_name: str,
    vars: Dict[str, Any],
) -> Tuple[Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
    try:
        resolved = resolve_tier4_inputs(recipe_name, vars)
    except KeyError as exc:
        return None, error("UNKNOWN_ERROR", 500, "Recipe configuration error.", str(exc))

    for type_name in recipe_input_types(recipe_name):
        value = resolved.get(type_name)
        if value is None:
            return None, error(
                "MISSING_INPUT",
                400,
                f"Missing required input: {type_name}",
                f"{recipe_name} requires {type_name} via tier4_var_mapping.",
            )
        ok, errs = validate_cdm(type_name, value)
        if not ok:
            return None, error(
                "VALIDATION_ERROR",
                400,
                f"Invalid {type_name} payload.",
                "; ".join(errs[:5]),
            )
    return resolved, None


def run_analyzer(
    recipe_name: str,
    vars: Dict[str, Any],
    analyze: Callable[[Dict[str, Any]], Dict[str, Any]],
    *,
    error_message: str = "Analysis failed.",
) -> Dict[str, Any]:
    resolved, err = load_tier4_inputs(recipe_name, vars)
    if err:
        return err
    try:
        return analyze(resolved)
    except Exception as exc:
        return error("UNKNOWN_ERROR", 500, error_message, str(exc))
