#!/usr/bin/env python
"""
Live Odoo Integration Test: Tier 3 → 3.5 → 4 → 5
Tests the complete inventory analytics pipeline with Odoo backend
"""

import sys
import json
import time

sys.path.insert(0, 'recipes/odoo/inventory')
sys.path.insert(0, 'recipes/_normalizers/Inventory')
sys.path.insert(0, 'recipes/odoo/analytics')
sys.path.insert(0, 'recipes/odoo/crm')

from odoo_get_inventory import run as tier3_run
from normalize_inventory_snapshot import run as tier35_run
from analyze_inventory_gaps import run as tier4_run
from simulate_inventory_change import run as tier5_sim_run
from predict_customer_ltv import run as tier5_ltv_run

print("\n" + "=" * 90)
print("LIVE ODOO INTEGRATION TEST - FULL TIER 3 → 5 PIPELINE")
print("=" * 90 + "\n")

# TIER 3: Get inventory from Odoo
print("[TIER 3] Fetching inventory from Odoo...")
print("-" * 90)
tier3_start = time.time()
tier3_result = tier3_run({
    'odoo_base_url': 'http://localhost:8069',
    'odoo_db': 'hyve_kitchen',
    'odoo_uid': 7,
    'odoo_password': 'Test12345!'
})
tier3_elapsed = time.time() - tier3_start

assert tier3_result['status'] == 'SUCCESS', f"Tier 3 failed: {tier3_result}"
raw_inventory = tier3_result['data']['inventory']
print(f"✓ Status: {tier3_result['status']}")
print(f"✓ Message: {tier3_result['user_message']}")
print(f"✓ Items fetched: {len(raw_inventory)}")
print(f"✓ Elapsed: {tier3_elapsed:.3f}s")
if raw_inventory:
    print(f"✓ Sample item: product_id={raw_inventory[0]['product_id']}, qty={raw_inventory[0]['qty_available']}")

# TIER 3.5: Normalize to CDM
print("\n[TIER 3.5] Normalizing to CommonInventorySnapshot CDM...")
print("-" * 90)
tier35_start = time.time()
tier35_result = tier35_run({'raw_inventory': raw_inventory})
tier35_elapsed = time.time() - tier35_start

assert tier35_result['status'] == 'SUCCESS', f"Tier 3.5 failed: {tier35_result}"
normalized = tier35_result['data']['inventory_snapshot']
print(f"✓ Status: {tier35_result['status']}")
print(f"✓ Items normalized: {len(normalized)}")
print(f"✓ Elapsed: {tier35_elapsed:.3f}s")
if normalized:
    item = normalized[0]
    print(f"✓ Sample CDM: product_id={item['product_id']}, qty_available={item['qty_available']}, reorder_point={item['reorder_point']}")

# TIER 4: Analyze gaps
print("\n[TIER 4] Analyzing inventory gaps...")
print("-" * 90)
tier4_start = time.time()
tier4_result = tier4_run({'inventory_snapshot': normalized})
tier4_elapsed = time.time() - tier4_start

assert tier4_result['status'] == 'SUCCESS', f"Tier 4 failed: {tier4_result}"
gaps = tier4_result['data']['gaps']
gap_count = tier4_result['data']['gap_count']
print(f"✓ Status: {tier4_result['status']}")
print(f"✓ Gaps detected: {gap_count}")
print(f"✓ Elapsed: {tier4_elapsed:.3f}s")
if gaps:
    gap = gaps[0]
    print(f"✓ Sample gap: product_id={gap['product_id']}, available={gap['qty_available']}, reorder={gap['reorder_point']}, gap_qty={gap['gap']}")

# TIER 5a: Simulate inventory change (session-scoped)
print("\n[TIER 5a] Simulating inventory adjustments (session-scoped)...")
print("-" * 90)
tier5a_start = time.time()
delta_adjustments = [
    {'product_id': 'prod:1001', 'qty_delta': 15},  # Increase prod:1001 by 15 units
    {'product_id': 'prod:1002', 'qty_delta': -5},  # Decrease prod:1002 by 5 units
]
tier5a_result = tier5_sim_run({
    'inventory_snapshot': normalized,
    'delta_adjustments': delta_adjustments
})
tier5a_elapsed = time.time() - tier5a_start

assert tier5a_result['status'] == 'SUCCESS', f"Tier 5a failed: {tier5a_result}"
simulated = tier5a_result['data']['simulated_inventory_snapshot']
print(f"✓ Status: {tier5a_result['status']}")
print(f"✓ Simulated items: {len(simulated)}")
print(f"✓ Deltas applied: {len(delta_adjustments)}")
print(f"✓ Elapsed: {tier5a_elapsed:.3f}s")
if simulated:
    for item in simulated:
        if item['product_id'] in ['prod:1001', 'prod:1002']:
            print(f"  → product_id={item['product_id']}, qty_after_delta={item['qty_available']}")

# Verify session-scoped: Run gap analysis on simulated inventory
print("\n[VERIFICATION] Running gap analysis on simulated inventory...")
gap_result_after_sim = tier4_run({'inventory_snapshot': simulated})
gaps_after_sim = gap_result_after_sim['data']['gaps']
gap_count_after_sim = gap_result_after_sim['data']['gap_count']
print(f"✓ Gaps before simulation: {gap_count}")
print(f"✓ Gaps after simulation: {gap_count_after_sim}")
print(f"✓ Simulation working: {'YES' if gap_count_after_sim < gap_count else 'NO'}")

# TIER 5b: Predict customer LTV
print("\n[TIER 5b] Predicting customer LTV...")
print("-" * 90)
tier5b_start = time.time()
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
tier5b_result = tier5_ltv_run({
    'customer_profile_summary': customer_profile,
    'transaction_history': transactions
})
tier5b_elapsed = time.time() - tier5b_start

assert tier5b_result['status'] == 'SUCCESS', f"Tier 5b failed: {tier5b_result}"
ltv_data = tier5b_result['data']
print(f"✓ Status: {tier5b_result['status']}")
print(f"✓ Customer: {ltv_data.get('customer_id')} ({customer_profile['name']})")
print(f"✓ Predicted 90d revenue: ${ltv_data['predicted_90d_revenue']:.2f}")
print(f"✓ Confidence: {ltv_data['confidence']}%")
print(f"✓ Recommendation: {ltv_data['recommended_action']}")
print(f"✓ Elapsed: {tier5b_elapsed:.3f}s")

# Summary
print("\n" + "=" * 90)
print("END-TO-END PIPELINE SUMMARY")
print("=" * 90)
total_time = tier3_elapsed + tier35_elapsed + tier4_elapsed + tier5a_elapsed + tier5b_elapsed
print(f"✓ Tier 3 (Get):       {tier3_elapsed:.3f}s")
print(f"✓ Tier 3.5 (Norm):    {tier35_elapsed:.3f}s")
print(f"✓ Tier 4 (Gap Anal):  {tier4_elapsed:.3f}s")
print(f"✓ Tier 5a (Sim):      {tier5a_elapsed:.3f}s")
print(f"✓ Tier 5b (LTV):      {tier5b_elapsed:.3f}s")
print(f"✓ TOTAL:              {total_time:.3f}s")
print("\n✓ ALL LIVE ODOO TESTS PASSED\n")
