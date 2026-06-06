#!/usr/bin/env python
import sys
import json
import traceback

sys.path.insert(0, 'recipes/odoo/inventory')

try:
    print('Importing Tier 3 getter...', flush=True)
    from odoo_get_inventory import run
    
    print('Calling Tier 3 getter with Odoo config...', flush=True)
    result = run({
        'odoo_base_url': 'http://localhost:8069',
        'odoo_db': 'hyve_kitchen',
        'odoo_uid': 7,
        'odoo_password': 'Test12345!'
    })
    print('Result received.')
    print(json.dumps(result, indent=2))
except Exception as e:
    print(f'Error: {e}', flush=True)
    traceback.print_exc()
