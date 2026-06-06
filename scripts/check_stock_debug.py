import json
import random
import urllib.request

base_url = 'http://localhost:8069'
url = f'{base_url}/jsonrpc'

def rpc(service, method, *args):
    payload = {
        'jsonrpc': '2.0',
        'method': 'call',
        'id': random.randint(1, 999999999),
        'params': {
            'service': service,
            'method': method,
            'args': list(args),
        },
    }
    req = urllib.request.Request(
        url=url,
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.load(resp)

print('Odoo version:', rpc('common', 'version'))
login = rpc('common', 'login', 'hyve_kitchen', 'test_recipe_user@example.com', 'Test12345!')
print('login:', login)
uid = login.get('result')
for domain in [[('name', '=', 'stock')], [('name', 'ilike', 'stock')], [('shortdesc', 'ilike', 'Inventory')], [('state', '=', 'uninstalled')], [('state', '=', 'installed')]]:
    print('DOMAIN', domain)
    response = rpc(
        'object',
        'execute_kw',
        'hyve_kitchen',
        uid,
        'Test12345!',
        'ir.module.module',
        'search_read',
        [domain],
        {'fields': ['id', 'name', 'state', 'shortdesc'], 'limit': 20},
    )
    print(json.dumps(response, indent=2))
