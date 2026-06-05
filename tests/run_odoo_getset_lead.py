import json
import os
import sys
import urllib.request

# Ensure repo root is on path
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from recipes.odoo_getset_lead import run


def json_rpc(method, params):
    payload = json.dumps({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': params,
    }).encode('utf-8')
    request = urllib.request.Request(
        CONFIG['url'], data=payload, headers={'Content-Type': 'application/json'}
    )
    return json.loads(urllib.request.urlopen(request, timeout=15).read().decode())


def login(username, password):
    params = {
        'service': 'common',
        'method': 'login',
        'args': [CONFIG['db'], username, password],
    }
    return json_rpc('call', params)


def main():
    global CONFIG
    CONFIG = {
        'url': os.environ.get('ODOO_BASE_URL', 'http://localhost:8069/jsonrpc'),
        'db': os.environ.get('ODOO_DB', 'hyve_kitchen'),
        'username': os.environ.get('ODOO_USERNAME', 'test_recipe_user@example.com'),
        'password': os.environ.get('ODOO_PASSWORD', 'Test12345!'),
    }

    login_result = login(CONFIG['username'], CONFIG['password'])
    print('login result', json.dumps(login_result, indent=2))
    if 'result' not in login_result:
        raise SystemExit('Login failed')

    uid = login_result['result']
    print('uid', uid)

    vars = {
        'odoo_base_url': CONFIG['url'].replace('/jsonrpc', ''),
        'odoo_db': CONFIG['db'],
        'odoo_uid': uid,
        'odoo_password': CONFIG['password'],
        'lead_name': 'Test Lead',
        'lead_email': 'test+hyve@example.com',
        'lead_phone': '',
        'face_hash': os.environ.get('TEST_FACE_HASH', ''),
    }

    print('Running ododo_getset_lead.run(vars) with: ')
    print({k: (v if k != 'odoo_password' else '***') for k, v in vars.items()})

    result = run(vars)
    print('Result envelope:\n', result)


if __name__ == "__main__":
    main()
