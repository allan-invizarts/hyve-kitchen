import json
import random
import urllib.request

BASE_URL = 'http://localhost:8069'
URL = f'{BASE_URL}/jsonrpc'
DB = 'hyve_kitchen'
USERNAME = 'admin'
PASSWORD = 'admin'


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
        url=URL,
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def login():
    result = rpc('common', 'login', DB, USERNAME, PASSWORD)
    if 'result' not in result:
        raise RuntimeError(f'Login failed: {result}')
    return result['result']


def find_stock_module(uid):
    response = rpc(
        'object',
        'execute_kw',
        DB,
        uid,
        PASSWORD,
        'ir.module.module',
        'search_read',
        [[('name', '=', 'stock')]],
        {'fields': ['id', 'name', 'state', 'shortdesc'], 'limit': 10},
    )
    if isinstance(response, dict) and 'result' in response:
        return response['result']
    return response


def install_module(uid, module_id):
    return rpc(
        'object',
        'execute_kw',
        DB,
        uid,
        PASSWORD,
        'ir.module.module',
        'button_immediate_install',
        [[module_id]],
    )


def main():
    print('Logging into Odoo...')
    uid = login()
    print('Authenticated uid:', uid)

    modules = find_stock_module(uid)
    print('Stock module lookup:', json.dumps(modules, indent=2))
    if not modules:
        raise SystemExit('Stock module record not found in ir.module.module.')

    module = modules[0]
    print('Found stock module:', module)
    state = module.get('state')
    if state == 'installed':
        print('Stock module is already installed.')
        return
    if state == 'uninstalled':
        print('Installing stock module with id', module['id'])
        result = install_module(uid, module['id'])
        print('Install result:', result)
        print('Stock module install was triggered. It may take a moment to complete.')
        return
    print('Stock module state is', state, 'and may require another action.')


if __name__ == '__main__':
    main()
