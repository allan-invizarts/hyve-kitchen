"""Tier 4 Full Chain Test: CRUD → Normalize → Analyze

This test demonstrates the complete recipe chain:
1. Tier 3: Create/read lead from Odoo (raw)
2. Tier 3.5: Normalize to CommonCustomerProfile (CDM)
3. Tier 4: Analyze for risk/engagement metrics (analytics)
"""

import sys
import json
import importlib.util
from pathlib import Path

# Add recipes to path
recipes_path = Path(__file__).parent.parent
sys.path.insert(0, str(recipes_path))

try:
    from odoo.crm.odoo_crm_crud import run as crud_run
except ImportError:
    crud_run = None

try:
    from _normalizers.CommonCustomerProfile.normalize_customer_profile import run as normalize_run
except ImportError:
    normalize_run = None

try:
    from odoo.crm.analyze_customer_profile_summary import run as analyze_run
except ImportError:
    # Fallback: import from local path directly
    import importlib.util
    analyze_path = recipes_path / "recipes" / "odoo" / "crm" / "analyze_customer_profile_summary.py"
    spec = importlib.util.spec_from_file_location(
        "analyze_customer_profile_summary",
        str(analyze_path)
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    analyze_run = module.run


def test_tier4_chain():
    """Full chain: CRUD -> Normalize -> Analyze"""
    
    if not crud_run or not normalize_run:
        print("\n[CHAIN TEST] Skipping: CRUD/Normalizer modules not available")
        print("             (Install Odoo dependencies or run with --mode sample)")
        return True  # Skip, don't fail
    
    print("\n" + "="*70)
    print("TIER 4 CHAIN TEST: Raw Odoo Lead → CDM → Analytics")
    print("="*70)
    
    # Configuration
    ODOO_CONFIG = {
        "odoo_base_url": "http://localhost:8069",
        "odoo_db": "odoo",
        "odoo_uid": 2,
        "odoo_password": "admin",
    }
    
    # Step 1: Create a test lead via Tier 3 CRUD
    print("\n[TIER 3] Creating test lead...")
    create_result = crud_run({
        **ODOO_CONFIG,
        "action": "create",
        "lead_name": "Test Tier4 Customer",
        "lead_email": "tier4test@example.com",
        "lead_phone": "+1-555-7777",
    })
    
    if create_result["status"] != "SUCCESS":
        print(f"✗ Failed to create lead: {create_result['system_message']}")
        return False
    
    lead_id = create_result["data"]["lead_id"]
    print(f"✓ Created lead (ID: {lead_id})")
    
    # Step 2: Read the lead via Tier 3 CRUD
    print("\n[TIER 3] Reading raw lead...")
    read_result = crud_run({
        **ODOO_CONFIG,
        "action": "read",
        "lead_id": lead_id,
    })
    
    if read_result["status"] != "SUCCESS":
        print(f"✗ Failed to read lead: {read_result['system_message']}")
        return False
    
    raw_lead = read_result["data"]["lead"]
    print(f"✓ Read raw lead: {raw_lead.get('name')} ({raw_lead.get('email_from')})")
    
    # Step 3: Normalize via Tier 3.5
    print("\n[TIER 3.5] Normalizing to CommonCustomerProfile...")
    normalize_result = normalize_run({
        "raw_lead": raw_lead,
        "source_system": "odoo",
    })
    
    if normalize_result["status"] != "SUCCESS":
        print(f"✗ Failed to normalize: {normalize_result['system_message']}")
        return False
    
    normalized_profile = normalize_result["data"]["normalized_profile"]
    print(f"✓ Normalized profile: {normalized_profile.get('name')}")
    print(f"  Fields: customer_id={normalized_profile.get('customer_id')}, "
          f"email={normalized_profile.get('email')}, phone={normalized_profile.get('phone')}")
    
    # Step 4: Analyze via Tier 4
    print("\n[TIER 4] Analyzing customer profile...")
    analyze_result = analyze_run({
        "customer_profile": normalized_profile,
    })
    
    if analyze_result["status"] != "SUCCESS":
        print(f"✗ Failed to analyze: {analyze_result['system_message']}")
        return False
    
    risk_score = analyze_result["data"]["risk_score"]
    engagement_tier = analyze_result["data"]["engagement_tier"]
    risk_narrative = analyze_result["data"]["risk_narrative"]
    
    print(f"✓ Analysis complete:")
    print(f"  Risk Score: {risk_score}")
    print(f"  Engagement Tier: {engagement_tier}")
    print(f"  Narrative: {risk_narrative}")
    
    # Step 5: Clean up
    print("\n[CLEANUP] Deleting test lead...")
    delete_result = crud_run({
        **ODOO_CONFIG,
        "action": "delete",
        "lead_id": lead_id,
    })
    
    if delete_result["status"] == "SUCCESS":
        print(f"✓ Deleted test lead (ID: {lead_id})")
    else:
        print(f"✗ Failed to delete: {delete_result['system_message']}")
    
    # Summary
    print("\n" + "="*70)
    print("CHAIN TEST PASSED ✓")
    print("="*70)
    print(f"\nSummary:")
    print(f"  Input (Raw): {raw_lead.get('name')} | {raw_lead.get('email_from')}")
    print(f"  After T3.5 (CDM): {normalized_profile.get('name')} | {normalized_profile.get('email')}")
    print(f"  After T4 (Analytics): Risk={risk_score}, Tier={engagement_tier}")
    print()
    
    return True


def test_tier4_with_sample_data():
    """Test Tier 4 analyzer with pre-defined sample data (no Odoo needed)"""
    
    print("\n" + "="*70)
    print("TIER 4 STANDALONE TEST: Sample CDM → Analytics")
    print("="*70)
    
    # Sample CommonCustomerProfile (what Tier 3.5 would return)
    sample_profile = {
        "customer_id": 999,
        "name": "Jane Smith",
        "email": "jane.smith@company.com",
        "phone": "+1-555-0099",
        "created_date": "2026-01-15T08:00:00Z",
        "last_activity": "2026-06-04T14:20:00Z",
        "loyalty_status": {
            "points_balance": 500,
            "tier": "silver",
        }
    }
    
    print("\nInput Profile (CommonCustomerProfile):")
    print(f"  Name: {sample_profile['name']}")
    print(f"  Email: {sample_profile['email']}")
    print(f"  Loyalty: {sample_profile['loyalty_status']['tier']} tier")
    
    # Run Tier 4 analyzer
    print("\n[TIER 4] Analyzing sample profile...")
    result = analyze_run({"customer_profile": sample_profile})
    
    if result["status"] != "SUCCESS":
        print(f"✗ Analysis failed: {result['system_message']}")
        return False
    
    print(f"✓ Analysis complete:")
    print(f"  Risk Score: {result['data']['risk_score']}")
    print(f"  Engagement Tier: {result['data']['engagement_tier']}")
    print(f"  Narrative: {result['data']['risk_narrative']}")
    
    print("\n" + "="*70)
    print("STANDALONE TEST PASSED ✓")
    print("="*70 + "\n")
    
    return True


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Test Tier 4 analyzer chain")
    parser.add_argument(
        "--mode",
        choices=["chain", "sample", "both"],
        default="both",
        help="Test mode: chain (full CRUD chain), sample (standalone), or both",
    )
    
    args = parser.parse_args()
    
    all_passed = True
    
    if args.mode in ("sample", "both"):
        if not test_tier4_with_sample_data():
            all_passed = False
    
    if args.mode in ("chain", "both"):
        if not test_tier4_chain():
            all_passed = False
    
    if not all_passed:
        sys.exit(1)
