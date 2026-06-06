import json
import random
import urllib.request
import urllib.error
import time

base_url = 'http://localhost:8069'
url = f'{base_url}/jsonrpc'

def rpc(service, method, *args, timeout=30):
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
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def login(db, username, password):
    return rpc('common', 'login', db, username, password)


def install_module(db, uid, password, module_name):
    # find module
    res = rpc('object', 'execute_kw', db, uid, password, 'ir.module.module', 'search_read', [[('name','=', module_name)]], {'fields': ['id','name','state'], 'limit': 10})
    result = res.get('result') if isinstance(res, dict) else res
    if not result:
        print('Module not found in ir.module.module. Try updating module list and retrying.')
        return False
    mod = result[0]
    mod_id = mod.get('id')
    state = mod.get('state')
    print(f'Module {module_name} found: id={mod_id}, state={state}')
    if state == 'installed':
        print('Module already installed.')
        return True
    # try immediate install
    try:
        print('Calling button_immediate_install...')
        rpc('object', 'execute_kw', db, uid, password, 'ir.module.module', 'button_immediate_install', [[mod_id]])
        # wait a bit and re-read state
        time.sleep(3)
        res2 = rpc('object', 'execute_kw', db, uid, password, 'ir.module.module', 'read', [[mod_id]], {'fields': ['id','name','state']})
        out = res2.get('result') if isinstance(res2, dict) else res2
        if out and out[0].get('state') == 'installed':
            print('Module installed successfully.')
            return True
        else:
            print('Install call returned but module state is:', out)
            return False
    except Exception as exc:
        print('Error during install call:', exc)
        return False


def main():
    db = 'hyve_kitchen'
    admin_user = 'admin'
    admin_pass = 'admin'
    print('Logging in as admin to install modules...')
    try:
        login_res = login(db, admin_user, admin_pass)
        uid = login_res.get('result')
        print('admin uid:', uid)
        if not uid:
            raise RuntimeError('Admin login returned no uid')
        password_used = admin_pass
    except Exception as exc:
        print('Admin login failed:', exc)
        # fallback: try test_recipe_user
        try:
            print('Falling back to test_recipe_user@example.com')
            fallback_user = 'test_recipe_user@example.com'
            fallback_pass = 'Test12345!'
            login_res = login(db, fallback_user, fallback_pass)
            uid = login_res.get('result')
            print('fallback uid:', uid)
            if not uid:
                raise RuntimeError('Fallback login returned no uid')
            password_used = fallback_pass
        except Exception as exc2:
            print('Fallback login failed too:', exc2)
            return
    if not uid:
        print('No uid obtained; cannot proceed.')
        return

    # Use the password that matched the authenticated user
    success = install_module(db, uid, password_used, 'stock')
    if success:
        print('Done: stock module active.')
    else:
        print('Failed to install stock module on first attempt. Trying to update module list and retry...')
        try:
            # attempt to update the module list
            print('Calling update_module_list...')
            rpc('object', 'execute_kw', db, uid, password_used, 'ir.module.module', 'update_list')
        except Exception as exc:
            print('update_list failed:', exc)
        # retry install
        retry = install_module(db, uid, password_used, 'stock')
        if retry:
            print('Done: stock module active after retry.')
        else:
            print('Failed to install stock module. Consider enabling addons path, updating module list from UI, or installing via Odoo UI.')

if __name__ == '__main__':
    main()
