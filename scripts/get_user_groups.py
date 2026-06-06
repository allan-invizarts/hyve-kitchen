#!/usr/bin/env python
import urllib.request, json, random

# Get test_recipe_user's groups
payload = {
    'jsonrpc': '2.0',
    'method': 'call',
    'id': random.randint(1,999999999),
    'params': {
        'service': 'object',
        'method': 'execute_kw',
        'args': ['hyve_kitchen', 1, 'admin', 'res.users', 'read', [7], ['login', 'groups_id']],
    }
}

req = urllib.request.Request('http://localhost:8069/jsonrpc', data=json.dumps(payload).encode('utf-8'), headers={'Content-Type': 'application/json'}, method='POST')
resp = urllib.request.urlopen(req, timeout=10)
result = json.load(resp)

if 'result' in result:
    user = result['result'][0]
    print('User:', user['login'])
    print('Current groups:', user['groups_id'])
else:
    print('Error:', json.dumps(result, indent=2)[:500])
