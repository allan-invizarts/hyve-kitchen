import json
import random
import urllib.request
import urllib.error

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


def login(db, username, password):
    return rpc('common', 'login', db, username, password)


def main():
    print('Checking local Odoo availability...')
    try:
        version_result = rpc('common', 'version')
        print('Odoo version response:', version_result.get('result'))
    except Exception as exc:
        print('Unable to reach Odoo JSON-RPC:', exc)
        raise SystemExit(1)

    db = 'hyve_kitchen'
    username = 'test_recipe_user@example.com'
    password = 'Test12345!'

    try:
        print('Logging in as', username)
        login_result = login(db, username, password)
        print('Login result:', login_result)
        uid = login_result.get('result')
        if not uid:
            raise RuntimeError('Login failed or returned no uid')
        print('Authenticated uid:', uid)
    except Exception as exc:
        print('Error during login:', exc)
        raise SystemExit(1)

    try:
        module_name = 'stock'
        response = rpc(
            'object',
            'execute_kw',
            db,
            uid,
            password,
            'ir.module.module',
            'search_read',
            [[('name', '=', module_name)]],
            {'fields': ['id', 'name', 'state', 'installable', 'shortdesc'], 'limit': 10},
        )
        query = response.get('result', []) if isinstance(response, dict) else response
        print('Stock module query result:')
        print(json.dumps(query, indent=2))
        if not query:
            print('Stock module not found in ir.module.module. It likely is not installed or available.')
            raise SystemExit(1)

        module = query[0]
        state = module.get('state')
        print('Stock module state:', state)

        if state == 'uninstalled':
            if not module.get('installable', False):
                raise SystemExit('Stock module is uninstalled but not installable from this Odoo instance.')
            print('Installing stock module...')
            install_result = rpc(
                'object',
                'execute_kw',
                db,
                uid,
                password,
                'ir.module.module',
                'button_immediate_install',
                [[module['id']]],
            )
            print('Install result:', install_result)
            print('Stock module installation triggered. Re-check state after a few seconds if needed.')
        elif state in ('installed', 'to upgrade'):
            print('Stock module is already installed or pending upgrade.')
        else:
            print('Stock module state is', state, 'and requires no action from this script.')
    except Exception as exc:
        print('Error querying or installing stock module:', exc)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
