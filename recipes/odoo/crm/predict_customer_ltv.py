"""Tier 5 Customer Lifetime Value Prediction.

Consumes CustomerProfileSummary from a Tier 4 analyzer and historical
CommonTransaction data to forecast future customer revenue.
"""

import json
from datetime import datetime, timedelta, timezone


def _parse_iso_date(date_str):
    if not date_str or not isinstance(date_str, str):
        return None
    try:
        return datetime.fromisoformat(date_str.replace("Z", "+00:00"))
    except ValueError:
        return None


def _recent_monthly_spend(transactions, window_days=90):
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(days=window_days)
    valid_amounts = []

    for tx in transactions or []:
        if not isinstance(tx, dict):
            continue
        amount = tx.get("amount")
        if amount is None:
            continue
        tx_date = _parse_iso_date(tx.get("transaction_date"))
        if tx_date is None:
            continue
        if tx_date >= cutoff:
            try:
                valid_amounts.append(float(amount))
            except (TypeError, ValueError):
                continue

    if not valid_amounts:
        return 0.0

    total = sum(valid_amounts)
    months = max(1.0, window_days / 30.0)
    return total / months


def _loyalty_multiplier(summary):
    loyalty = summary.get("loyalty_status") or {}
    tier = str(loyalty.get("tier", "")).strip().lower()

    if tier in ("gold", "platinum"):
        return 1.25
    if tier == "silver":
        return 1.15
    if tier == "bronze":
        return 1.05
    return 1.0


def _risk_multiplier(risk_score):
    try:
        score = float(risk_score)
    except (TypeError, ValueError):
        return 0.8

    if score <= 25:
        return 1.2
    if score <= 50:
        return 1.0
    if score <= 75:
        return 0.9
    return 0.8


def _engagement_boost(engagement_tier):
    tier = str(engagement_tier or "").strip().lower()
    if tier == "premium":
        return 1.15
    if tier == "standard":
        return 1.0
    if tier == "basic":
        return 0.9
    return 0.8


def _confidence_score(transaction_count, risk_score):
    score = 50
    if transaction_count >= 8:
        score += 30
    elif transaction_count >= 4:
        score += 15
    if risk_score is not None:
        try:
            score += max(0, int((100 - float(risk_score)) / 10))
        except (TypeError, ValueError):
            pass
    return min(100, score)


def run(vars: dict) -> dict:
    """Tier 5 simulator entry point.

    Input vars:
      - customer_profile_summary (dict): Tier 4 CustomerProfileSummary output
      - transaction_history (list[dict]): list of CommonTransaction records
      - projection_window_days (int, optional): prediction window in days

    Returns a prediction envelope.
    """
    try:
        summary = vars.get("customer_profile_summary")
        transactions = vars.get("transaction_history")
        window_days = vars.get("projection_window_days") or 90

        if not summary or not isinstance(summary, dict):
            return {
                "status": "VALIDATION_ERROR",
                "http_status": 400,
                "data": {},
                "user_message": "customer_profile_summary is required.",
                "system_message": "run() expects vars['customer_profile_summary'] to be a dict.",
            }

        if not isinstance(transactions, list):
            return {
                "status": "VALIDATION_ERROR",
                "http_status": 400,
                "data": {},
                "user_message": "transaction_history must be a list of CommonTransaction dicts.",
                "system_message": "run() expects vars['transaction_history'] to be a list.",
            }

        customer_id = summary.get("customer_id") or summary.get("id")
        if not customer_id:
            return {
                "status": "VALIDATION_ERROR",
                "http_status": 400,
                "data": {},
                "user_message": "customer_profile_summary must include customer_id.",
                "system_message": "Missing customer identifier in customer_profile_summary.",
            }

        risk_score = summary.get("risk_score")
        engagement_tier = summary.get("engagement_tier")

        monthly_spend = _recent_monthly_spend(transactions, 90)
        if monthly_spend <= 0:
            monthly_spend = 75.0

        prediction_multiplier = (
            _risk_multiplier(risk_score)
            * _loyalty_multiplier(summary)
            * _engagement_boost(engagement_tier)
        )

        projected_revenue = round(monthly_spend * 3 * prediction_multiplier, 2)
        confidence = _confidence_score(len(transactions), risk_score)

        if confidence >= 80:
            recommendation = "High confidence: consider a personalized loyalty offer."
        elif confidence >= 60:
            recommendation = "Medium confidence: monitor results and adapt offers." 
        else:
            recommendation = "Low confidence: gather more transaction history before acting."

        data = {
            "customer_id": customer_id,
            "predicted_90d_revenue": projected_revenue,
            "prediction_window_days": int(window_days),
            "confidence": confidence,
            "recommended_action": recommendation,
            "engagement_tier": engagement_tier,
            "risk_score": risk_score,
            "transaction_count": len(transactions),
            "prediction_date": datetime.now(timezone.utc).isoformat(),
        }

        return {
            "status": "SUCCESS",
            "http_status": 200,
            "data": data,
            "user_message": "Customer LTV prediction complete.",
            "system_message": f"Predicted ${projected_revenue} for customer {customer_id}.",
        }

    except Exception as exc:
        return {
            "status": "UNKNOWN_ERROR",
            "http_status": 500,
            "data": {},
            "user_message": "Failed to predict customer LTV.",
            "system_message": str(exc),
        }


if __name__ == "__main__":
    sample_summary = {
        "customer_id": 42,
        "name": "Allan Abendanio",
        "email": "allan@example.com",
        "phone": "+1-555-1234",
        "risk_score": 40,
        "engagement_tier": "standard",
        "loyalty_status": {"points_balance": 200, "tier": "silver"},
    }
    sample_transactions = [
        {"transaction_date": "2026-06-01T12:00:00Z", "amount": 75.00},
        {"transaction_date": "2026-05-24T15:30:00Z", "amount": 94.50},
        {"transaction_date": "2026-05-10T09:00:00Z", "amount": 122.75},
    ]
    result = run({
        "customer_profile_summary": sample_summary,
        "transaction_history": sample_transactions,
    })
    print(json.dumps(result, indent=2))
