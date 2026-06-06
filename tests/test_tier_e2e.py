#!/usr/bin/env python
"""End-to-end test: Tier 3 → Tier 3.5 → Tier 4 → Tier 5"""

import sys
import json

sys.path.insert(0, 'recipes/odoo/inventory')
sys.path.insert(0, 'recipes/_normalizers/Inventory')
sys.path.insert(0, 'recipes/odoo/analytics')
sys.path.insert(0, 'recipes/odoo/crm')

from odoo_get_inventory import run as tier3_run
from normalize_inventory_snapshot import run as tier35_run
from analyze_inventory_gaps import run as tier4_run
from simulate_inventory_change import run as tier5_sim_run
from predict_customer_ltv import run as tier5_ltv_run

print("=" * 80)
print("TIER 3 → 5 END-TO-END TEST")
print("=" * 80)

# TIER 3: Get inventory
print("\n[TIER 3] Fetching raw inventory...")
tier3_result = tier3_run({})
assert tier3_result['status'] == 'SUCCESS', f"Tier 3 failed: {tier3_result}"
raw_inventory = tier3_result['data']['inventory']
print(f"✓ Got {len(raw_inventory)} items from Tier 3")
print(f"  Sample: {json.dumps(raw_inventory[0], indent=2)[:200]}...")

# TIER 3.5: Normalize
print("\n[TIER 3.5] Normalizing inventory snapshot...")
tier35_result = tier35_run({'raw_inventory': raw_inventory})
assert tier35_result['status'] == 'SUCCESS', f"Tier 3.5 failed: {tier35_result}"
normalized_inventory = tier35_result['data']['inventory_snapshot']
print(f"✓ Normalized {len(normalized_inventory)} items")
print(f"  Sample: {json.dumps(normalized_inventory[0], indent=2)[:200]}...")

# TIER 4: Analyze gaps
print("\n[TIER 4] Analyzing inventory gaps...")
tier4_result = tier4_run({'inventory_snapshot': normalized_inventory})
assert tier4_result['status'] == 'SUCCESS', f"Tier 4 failed: {tier4_result}"
gaps = tier4_result['data']['gaps']
gap_count = tier4_result['data']['gap_count']
print(f"✓ Found {gap_count} gaps")
if gaps:
    print(f"  Sample gap: {json.dumps(gaps[0], indent=2)[:200]}...")

# TIER 5a: Simulate inventory change
print("\n[TIER 5a] Simulating inventory change...")
tier5sim_result = tier5_sim_run({
    'inventory_snapshot': normalized_inventory,
    'delta_adjustments': [
        {'product_id': 'prod:1001', 'qty_delta': 10},
        {'product_id': 'prod:1002', 'qty_delta': -5},
    ]
})
assert tier5sim_result['status'] == 'SUCCESS', f"Tier 5 simulator failed: {tier5sim_result}"
simulated_inventory = tier5sim_result['data']['simulated_inventory_snapshot']
print(f"✓ Simulated {len(simulated_inventory)} items")
print(f"  Sample (after delta): {json.dumps(simulated_inventory[0], indent=2)[:200]}...")

# TIER 5b: Predict customer LTV
print("\n[TIER 5b] Predicting customer LTV...")
customer_profile = {
    'customer_id': 999,
    'name': 'Test Customer',
    'risk_score': 50,
    'engagement_tier': 'premium',
    'loyalty_status': {'tier': 'silver'}
}
transactions = [
    {'transaction_date': '2026-06-01T12:00:00Z', 'amount': 100.00},
    {'transaction_date': '2026-05-25T10:00:00Z', 'amount': 150.00},
    {'transaction_date': '2026-05-10T14:00:00Z', 'amount': 75.00},
]
tier5ltv_result = tier5_ltv_run({
    'customer_profile_summary': customer_profile,
    'transaction_history': transactions
})
assert tier5ltv_result['status'] == 'SUCCESS', f"Tier 5 LTV failed: {tier5ltv_result}"
ltv_data = tier5ltv_result['data']
print(f"✓ Predicted LTV")
print(f"  Predicted 90d revenue: ${ltv_data['predicted_90d_revenue']}")
print(f"  Confidence: {ltv_data['confidence']}%")
print(f"  Recommendation: {ltv_data['recommended_action']}")

print("\n" + "=" * 80)
print("✓ ALL TIERS PASSED END-TO-END TEST")
print("=" * 80)
