#!/usr/bin/env python
import urllib.request, json, random, time

print('Testing search_read on stock.quant with test_recipe_user (after permissions)...')
start = time.time()

payload = {
    'jsonrpc': '2.0',
    'method': 'call',
    'id': random.randint(1,999999999),
    'params': {
        'service': 'object',
        'method': 'execute_kw',
        'args': [
            'hyve_kitchen',
            7,
            'Test12345!',
            'stock.quant',
            'search_read',
            [],
        ],
        'kwargs': {
            'fields': ['id', 'product_id', 'quantity', 'reserved_quantity', 'location_id'],
            'limit': 20
        }
    }
}

req = urllib.request.Request('http://localhost:8069/jsonrpc', data=json.dumps(payload).encode('utf-8'), headers={'Content-Type': 'application/json'}, method='POST')
resp = urllib.request.urlopen(req, timeout=10)
result = json.load(resp)
elapsed = time.time() - start

print('Result (elapsed {:.2f}s):'.format(elapsed))
if 'result' in result:
    print('SUCCESS! Got {} quants'.format(len(result['result'])))
    if result['result']:
        print('Sample quant:')
        print(json.dumps(result['result'][0], indent=2))
else:
    print('ERROR:')
    print(json.dumps(result, indent=2)[:800])
