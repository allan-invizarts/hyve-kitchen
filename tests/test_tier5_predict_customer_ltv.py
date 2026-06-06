"""Tier 5 test harness: predict_customer_ltv."""

import sys
import json
from pathlib import Path

recipes_path = Path(__file__).parent.parent
sys.path.insert(0, str(recipes_path))

try:
    from odoo.crm.predict_customer_ltv import run as predict_run
except ImportError:
    from importlib.util import spec_from_file_location, module_from_spec
    predict_path = recipes_path / "recipes" / "odoo" / "crm" / "predict_customer_ltv.py"
    spec = spec_from_file_location("predict_customer_ltv", str(predict_path))
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    predict_run = module.run

try:
    from odoo.crm.analyze_customer_profile_summary import run as analyze_run
except ImportError:
    from importlib.util import spec_from_file_location, module_from_spec
    analyze_path = recipes_path / "recipes" / "odoo" / "crm" / "analyze_customer_profile_summary.py"
    spec = spec_from_file_location(
        "analyze_customer_profile_summary",
        str(analyze_path)
    )
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    analyze_run = module.run


def test_tier5_predict_customer_ltv():
    """Run a Tier 5 LTV prediction using Tier 4 summary + sample transactions."""
    sample_profile = {
        "customer_id": 999,
        "name": "Jamie Customer",
        "email": "jamie.customer@company.com",
        "phone": "+1-555-0101",
        "created_date": "2026-03-01T10:00:00Z",
        "last_activity": "2026-06-01T09:15:00Z",
        "loyalty_status": {
            "points_balance": 260,
            "tier": "silver",
        },
    }

    sample_transactions = [
        {"transaction_date": "2026-05-25T14:00:00Z", "amount": 95.00},
        {"transaction_date": "2026-05-10T10:30:00Z", "amount": 120.00},
        {"transaction_date": "2026-04-18T16:20:00Z", "amount": 80.00},
    ]

    analyze_result = analyze_run({"customer_profile": sample_profile})
    if analyze_result["status"] != "SUCCESS":
        print("✗ Tier 4 summary generation failed")
        print(json.dumps(analyze_result, indent=2))
        return False

    summary = analyze_result["data"]["summary"]
    predict_result = predict_run({
        "customer_profile_summary": summary,
        "transaction_history": sample_transactions,
    })

    if predict_result["status"] != "SUCCESS":
        print("✗ Tier 5 prediction failed")
        print(json.dumps(predict_result, indent=2))
        return False

    print("\nTIER 5 PREDICT CUSTOMER LTV TEST")
    print(json.dumps(predict_result, indent=2))
    return True


if __name__ == "__main__":
    success = test_tier5_predict_customer_ltv()
    sys.exit(0 if success else 1)
