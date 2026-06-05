"""Tier 4 Customer Profile Summary Analyzer.

Consumes CommonCustomerProfile (from Tier 3.5 normalizer) and returns
engagement/risk analytics without touching the source system.
"""

import json
from datetime import datetime, timedelta


def _risk_score(profile: dict) -> float:
    """
    Compute engagement risk score (0-100).
    - Low email/phone presence = high risk
    - Long account age = lower risk
    - Recent activity = lower risk
    """
    score = 50.0  # baseline
    
    # Email presence
    if not profile.get("email"):
        score += 25
    
    # Phone presence
    if not profile.get("phone"):
        score += 15
    
    # Loyalty status check
    loyalty = profile.get("loyalty_status")
    if loyalty:
        if loyalty.get("points_balance", 0) < 100:
            score += 10
        if loyalty.get("tier") in ("bronze", "none"):
            score += 5
    
    # Account age (newer accounts have higher risk)
    created_date_str = profile.get("created_date")
    if created_date_str:
        try:
            created = datetime.fromisoformat(created_date_str.replace("Z", "+00:00"))
            age_days = (datetime.now(created.tzinfo) - created).days
            if age_days < 30:
                score += 20
            elif age_days < 90:
                score += 10
        except (ValueError, TypeError):
            pass
    
    # Recent activity
    last_activity_str = profile.get("last_activity")
    if last_activity_str:
        try:
            last_activity = datetime.fromisoformat(last_activity_str.replace("Z", "+00:00"))
            days_since = (datetime.now(last_activity.tzinfo) - last_activity).days
            if days_since > 180:
                score += 25
            elif days_since > 90:
                score += 15
            elif days_since > 30:
                score += 5
        except (ValueError, TypeError):
            pass
    
    return min(100.0, max(0.0, score))


def _engagement_tier(profile: dict) -> str:
    """
    Classify engagement tier based on profile attributes.
    """
    name = profile.get("name", "").strip().lower()
    email = profile.get("email", "").strip().lower()
    phone = profile.get("phone", "").strip().lower()
    loyalty = profile.get("loyalty_status") or {}
    
    # Premium: complete info + high loyalty
    if email and phone and loyalty.get("tier") in ("gold", "platinum", "silver"):
        return "premium"
    
    # Standard: has contact info
    if email and phone:
        return "standard"
    
    # Basic: name only or partial info
    if name or email or phone:
        return "basic"
    
    # Unknown: minimal data
    return "unknown"


def run(vars: dict) -> dict:
    """
    Tier 4 analyzer entry point.
    
    Input vars:
      - customer_profile (dict): CommonCustomerProfile from normalizer
      - analysis_window_days (int, optional): days to consider for recency
    
    Returns: {
      status, http_status, data: {
        customer_id, risk_score, engagement_tier, summary_dict
      }, user_message, system_message
    }
    """
    try:
        profile = vars.get("customer_profile")
        if not profile or not isinstance(profile, dict):
            return {
                "status": "VALIDATION_ERROR",
                "http_status": 400,
                "data": {},
                "user_message": "customer_profile (CommonCustomerProfile dict) is required.",
                "system_message": "run() expects vars['customer_profile'] to be a non-empty dict.",
            }
        
        customer_id = profile.get("customer_id") or profile.get("id")
        if not customer_id:
            return {
                "status": "VALIDATION_ERROR",
                "http_status": 400,
                "data": {},
                "user_message": "customer_profile must have customer_id or id field.",
                "system_message": "Missing customer identifier in profile.",
            }
        
        risk_score = _risk_score(profile)
        engagement_tier = _engagement_tier(profile)
        
        summary = {
            "customer_id": customer_id,
            "name": profile.get("name"),
            "email": profile.get("email"),
            "phone": profile.get("phone"),
            "risk_score": round(risk_score, 2),
            "engagement_tier": engagement_tier,
            "created_date": profile.get("created_date"),
            "last_activity": profile.get("last_activity"),
            "loyalty_status": profile.get("loyalty_status"),
        }
        
        # Determine risk narrative
        if risk_score >= 75:
            risk_narrative = "High risk: customer may churn soon. Recommend re-engagement campaign."
        elif risk_score >= 50:
            risk_narrative = "Medium risk: monitor for activity. Seasonal patterns may apply."
        else:
            risk_narrative = "Low risk: customer showing positive engagement signals."
        
        return {
            "status": "SUCCESS",
            "http_status": 200,
            "data": {
                "customer_id": customer_id,
                "risk_score": round(risk_score, 2),
                "engagement_tier": engagement_tier,
                "risk_narrative": risk_narrative,
                "summary": summary,
            },
            "user_message": f"Profile analysis complete. Risk: {engagement_tier.title()}, Engagement: {engagement_tier.title()}.",
            "system_message": f"Analyzed {customer_id}: risk_score={risk_score}, tier={engagement_tier}",
        }
    
    except Exception as exc:
        return {
            "status": "UNKNOWN_ERROR",
            "http_status": 500,
            "data": {},
            "user_message": "Failed to analyze customer profile.",
            "system_message": str(exc),
        }


if __name__ == "__main__":
    # Example usage
    sample_profile = {
        "customer_id": 42,
        "name": "Allan Abendanio",
        "email": "allan@example.com",
        "phone": "+1-555-1234",
        "created_date": "2026-05-01T10:00:00Z",
        "last_activity": "2026-06-04T15:30:00Z",
        "loyalty_status": {
            "points_balance": 250,
            "tier": "gold"
        }
    }
    
    result = run({"customer_profile": sample_profile})
    print(json.dumps(result, indent=2))
