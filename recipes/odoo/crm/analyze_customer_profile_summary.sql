-- Tier 4 analyzer: Customer Profile Summary
-- Consumes CommonCustomerProfile (from Tier 3.5 normalizer) and returns analytics summary
-- Apply this against your kitchen database after the cookbook_recipe schema is available.

BEGIN;

-- system / module / auth profile (reuse from Tier 3/3.5)
INSERT INTO cookbook_system (
    system_label, display_name, description, homepage_url, icon_filename, sort_order, created_by
)
VALUES (
    'odoo', 'Odoo ERP', 'Odoo ERP instance', 'http://localhost:8069', 'odoo.svg', 10, 'recipe-generator'
)
ON CONFLICT (system_label) DO NOTHING;

INSERT INTO cookbook_module (
    system_id, module_label, display_name, description, sort_order, created_by
)
SELECT id, 'crm', 'Customer Relationship Management', 'CRM module', 10, 'recipe-generator'
FROM cookbook_system WHERE system_label = 'odoo'
ON CONFLICT (system_id, module_label) DO NOTHING;

INSERT INTO cookbook_auth_profile (
    system_id, profile_label, display_name, description, is_active, sort_order, created_by
)
SELECT id, 'odoo_test', 'Odoo - Test Instance', 'Local docker-compose Odoo for development.', 1, 10, 'recipe-generator'
FROM cookbook_system WHERE system_label = 'odoo'
ON CONFLICT (system_id, profile_label) DO NOTHING;

-- Tier 4 recipe: analyzer that consumes CDM and returns analytics
WITH new_recipe AS (
    INSERT INTO cookbook_recipe (
        name, display_name, description,
        tier, cache_scope, cdm_output_type, cdm_input_types_csv,
        system_id, module_id, auth_profile_id, template_id,
        python_body, entrypoint,
        timeout_seconds, memory_mb,
        is_enabled, is_internal, required_role,
        is_read_only, is_chainable,
        cache_ttl_seconds, created_by
    )
    SELECT
        'analyze_customer_profile_summary',
        'Customer Profile Summary',
        'Tier 4 analyzer: consumes CommonCustomerProfile CDM and returns engagement/risk metrics.',
        'tier4', 'tenant', 'CustomerProfileSummary', 'CommonCustomerProfile',
        (SELECT id FROM cookbook_system WHERE system_label = 'odoo'),
        (SELECT id FROM cookbook_module
           WHERE module_label = 'crm'
             AND system_id = (SELECT id FROM cookbook_system WHERE system_label = 'odoo')),
        (SELECT id FROM cookbook_auth_profile WHERE profile_label = 'odoo_test'),
        NULL,
        $PY$
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
$PY$,
        'run',
        30, 64,
        1, 0, 'user',
        1, 1,
        120, 'recipe-generator'
    WHERE NOT EXISTS (SELECT 1 FROM cookbook_recipe WHERE name = 'analyze_customer_profile_summary')
)

-- Add dependency: Tier 4 analyzer depends on Tier 3.5 normalizer
INSERT INTO cookbook_recipe_dependency (
    recipe_id, depends_on_recipe_id, dependency_type, created_by
)
SELECT
    (SELECT id FROM cookbook_recipe WHERE name = 'analyze_customer_profile_summary'),
    (SELECT id FROM cookbook_recipe WHERE name = 'normalize_customer_profile'),
    'data',
    'recipe-generator'
WHERE NOT EXISTS (
    SELECT 1 FROM cookbook_recipe_dependency
    WHERE depends_on_recipe_id = (SELECT id FROM cookbook_recipe WHERE name = 'normalize_customer_profile')
      AND recipe_id = (SELECT id FROM cookbook_recipe WHERE name = 'analyze_customer_profile_summary')
);

-- Recipe vars (inputs to the analyzer)
INSERT INTO cookbook_recipe_var (
    recipe_id, var_name, var_type, is_required, description, display_label, sort_order, created_by
)
SELECT r.id, v.var_name, v.var_type, v.is_required, v.description, v.display_label, v.sort_order, 'recipe-generator'
FROM cookbook_recipe r
CROSS JOIN (VALUES
    ('customer_profile', 'object', 1, 'CommonCustomerProfile CDM dict from normalizer', 'Customer Profile', 10),
    ('analysis_window_days', 'integer', 0, 'Optional: days to consider for activity recency', 'Window (days)', 20)
) AS v(var_name, var_type, is_required, description, display_label, sort_order)
WHERE r.name = 'analyze_customer_profile_summary'
ON CONFLICT (recipe_id, var_name) DO NOTHING;

-- Recipe outputs
INSERT INTO cookbook_recipe_output (
    recipe_id, output_key, source_path, value_type, is_required, description, display_label, sort_order, created_by
)
SELECT r.id, 'risk_score', 'data.risk_score', 'float', 0, 'Customer risk score (0-100)', 'Risk Score', 10, 'recipe-generator'
FROM cookbook_recipe r
WHERE r.name = 'analyze_customer_profile_summary'
ON CONFLICT (recipe_id, output_key) DO NOTHING;

INSERT INTO cookbook_recipe_output (
    recipe_id, output_key, source_path, value_type, is_required, description, display_label, sort_order, created_by
)
SELECT r.id, 'engagement_tier', 'data.engagement_tier', 'string', 0, 'Customer engagement tier (premium/standard/basic/unknown)', 'Engagement Tier', 20, 'recipe-generator'
FROM cookbook_recipe r
WHERE r.name = 'analyze_customer_profile_summary'
ON CONFLICT (recipe_id, output_key) DO NOTHING;

INSERT INTO cookbook_recipe_output (
    recipe_id, output_key, source_path, value_type, is_required, description, display_label, sort_order, created_by
)
SELECT r.id, 'summary', 'data.summary', 'object', 0, 'Full customer profile summary with analytics', 'Summary', 30, 'recipe-generator'
FROM cookbook_recipe r
WHERE r.name = 'analyze_customer_profile_summary'
ON CONFLICT (recipe_id, output_key) DO NOTHING;

COMMIT;
