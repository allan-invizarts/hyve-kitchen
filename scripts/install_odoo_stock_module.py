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
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)

print('Logging in...')
login = rpc('common', 'login', 'odoo', 'admin', 'admin')
print('login result', login)
uid = login.get('result')
if not uid:
    raise SystemExit('Login failed')

db = 'odoo'
module_id = 533
print('Installing stock module id', module_id, 'into db', db)
install = rpc('object', 'execute_kw', db, uid, 'admin', 'ir.module.module', 'button_immediate_install', [[module_id]])
print('install response', install)

print('Re-checking stock state...')
response = rpc('object', 'execute_kw', 'hyve_kitchen', uid, 'Test12345!', 'ir.module.module', 'search_read', [[('id', '=', module_id)]], {'fields': ['id', 'name', 'state', 'shortdesc'], 'limit': 1})
print(json.dumps(response, indent=2))
