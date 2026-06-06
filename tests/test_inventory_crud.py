#!/usr/bin/env python
"""Quick test of inventory CRUD module."""

import sys
import json
sys.path.insert(0, 'recipes/odoo/inventory')
import odoo_inventory_crud as crud

# Test search action with no criteria (should return empty)
result = crud.run({'action': 'search', 'odoo_base_url': 'http://localhost:8069'})
print('INVENTORY CRUD TEST - SEARCH (no criteria)')
print(json.dumps(result, indent=2))

# Test validation error for create without fields
result2 = crud.run({'action': 'create', 'odoo_base_url': 'http://localhost:8069'})
print('\nINVENTORY CRUD TEST - CREATE (validation error)')
print(json.dumps(result2, indent=2))

# Test invalid action
result3 = crud.run({'action': 'invalid_action', 'odoo_base_url': 'http://localhost:8069'})
print('\nINVENTORY CRUD TEST - INVALID ACTION')
print(json.dumps(result3, indent=2))
