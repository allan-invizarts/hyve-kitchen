"""End-to-end sample test for inventory simulate flow:
normalize_inventory_snapshot -> simulate_inventory_change -> analyze_inventory_gaps
"""
import sys
import json
from pathlib import Path

recipes_path = Path(__file__).parent.parent
sys.path.insert(0, str(recipes_path))

# import normalizer
try:
    from _normalizers.Inventory.normalize_inventory_snapshot import run as norm_run
except Exception:
    from importlib.util import spec_from_file_location, module_from_spec
    p = recipes_path / 'recipes' / '_normalizers' / 'Inventory' / 'normalize_inventory_snapshot.py'
    spec = spec_from_file_location('normalize_inventory_snapshot', str(p))
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    norm_run = module.run

# import simulator
try:
    from odoo.analytics.simulate_inventory_change import run as sim_run
except Exception:
    from importlib.util import spec_from_file_location, module_from_spec
    p = recipes_path / 'recipes' / 'odoo' / 'analytics' / 'simulate_inventory_change.py'
    spec = spec_from_file_location('simulate_inventory_change', str(p))
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    sim_run = module.run

# import analyzer
try:
    from odoo.analytics.analyze_inventory_gaps import run as analyze_run
except Exception:
    from importlib.util import spec_from_file_location, module_from_spec
    p = recipes_path / 'recipes' / 'odoo' / 'analytics' / 'analyze_inventory_gaps.py'
    spec = spec_from_file_location('analyze_inventory_gaps', str(p))
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    analyze_run = module.run


def test_simulation_flow():
    # Step 1: normalize (sample)
    norm_res = norm_run({})
    if norm_res.get('status') != 'SUCCESS':
        print('✗ Normalizer failed')
        print(json.dumps(norm_res, indent=2))
        return False

    snapshot = norm_res['data'].get('inventory_snapshot')
    print('\nNormalized snapshot:')
    print(json.dumps(snapshot, indent=2))

    # Step 2: simulate adding stock to prod:1001
    sim_res = sim_run({'inventory_snapshot': snapshot, 'delta_adjustments': [{'product_id': 'prod:1001', 'qty_delta': 20}]})
    if sim_res.get('status') != 'SUCCESS':
        print('✗ Simulation failed')
        print(json.dumps(sim_res, indent=2))
        return False

    simulated = sim_res['data'].get('simulated_inventory_snapshot')
    print('\nSimulated snapshot:')
    print(json.dumps(simulated, indent=2))

    # Step 3: analyze gaps on simulated snapshot
    analyze_res = analyze_run({'inventory_snapshot': simulated})
    if analyze_res.get('status') != 'SUCCESS':
        print('✗ Analyzer failed')
        print(json.dumps(analyze_res, indent=2))
        return False

    print('\nGap analysis result:')
    print(json.dumps(analyze_res, indent=2))
    return True


if __name__ == '__main__':
    ok = test_simulation_flow()
    sys.exit(0 if ok else 1)
