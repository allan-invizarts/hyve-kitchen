import json
import uuid
import urllib.request

URL = 'http://localhost:8069/jsonrpc'
DB = 'hyve_kitchen'
USERNAME = 'test_recipe_user@example.com'
PASSWORD = 'Test12345!'

FIELDS_BASIC = [
    'id', 'name', 'email_from', 'phone', 'create_date', 'write_date', 'tag_ids'
]

EXTRA_FIELDS = [
    'x_hyve_face_hash', 'x_loyalty_tier', 'x_loyalty_points'
]


def json_rpc(service, method, params):
    payload = json.dumps({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
            'service': service,
            'method': method,
            'args': params,
        }
    }).encode('utf-8')
    req = urllib.request.Request(URL, data=payload, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.load(resp)


def login():
    res = json_rpc('common', 'login', [DB, USERNAME, PASSWORD])
    if 'result' in res and res['result']:
        return res['result']
    raise SystemExit(f"Login failed: {res}")


def search_lead(uid, email, phone, face_hash=''):
    domain = []
    if face_hash:
        domain = ['|', '|', ('x_hyve_face_hash', '=', face_hash), ('email_from', '=', email), ('phone', '=', phone)]
    else:
        if email and phone:
            domain = ['|', ('email_from', '=', email), ('phone', '=', phone)]
        elif email:
            domain = [('email_from', '=', email)]
        elif phone:
            domain = [('phone', '=', phone)]

    params = [DB, uid, PASSWORD, 'crm.lead', 'search_read', [domain], {'fields': FIELDS_BASIC, 'limit': 1}]
    return json_rpc('object', 'execute_kw', params)


def create_lead(uid, name, email, phone, face_hash=''):
    record = {
        'name': name,
        'email_from': email or False,
        'phone': phone or False,
    }
    if face_hash:
        record['x_hyve_face_hash'] = face_hash

    # create
    params = [DB, uid, PASSWORD, 'crm.lead', 'create', [record]]
    res = json_rpc('object', 'execute_kw', params)
    # create
    params = [DB, uid, PASSWORD, 'crm.lead', 'create', [record]]
    res = json_rpc('object', 'execute_kw', params)
    # read created (correct execute_kw ordering: args list, then kwargs dict)
    if 'result' in res and isinstance(res['result'], int):
        new_id = res['result']
        params = [DB, uid, PASSWORD, 'crm.lead', 'read', [[new_id]], {'fields': FIELDS_BASIC}]
        read_res = json_rpc('object', 'execute_kw', params)
        # attempt to fetch extra fields separately if they exist
        if 'result' in read_res and read_res['result']:
            try:
                params2 = [DB, uid, PASSWORD, 'crm.lead', 'read', [[new_id]], {'fields': EXTRA_FIELDS}]
                extra_res = json_rpc('object', 'execute_kw', params2)
                if 'result' in extra_res and extra_res['result']:
                    # merge extra fields into the read result
                    read_res['result'][0].update(extra_res['result'][0])
            except Exception:
                pass
        return read_res
    return res


if __name__ == '__main__':
    uid = login()
    unique = f"mock-{uuid.uuid4().hex[:8]}@hyve.ai"
    print('Using uid', uid)
    print('Trying to find or create lead for', unique)

    sr = search_lead(uid, unique, '')
    print('\nSEARCH_READ response:')
    print(json.dumps(sr, indent=2))

    lead = None
    if 'result' in sr and isinstance(sr['result'], list) and sr['result']:
        lead = sr['result'][0]
        print('\nFound lead:')
        print(json.dumps(lead, indent=2))
    else:
        cr = create_lead(uid, 'Mock Normalize Lead', unique, '', '')
        print('\nCREATE response:')
        print(json.dumps(cr, indent=2))
        if 'result' in cr and isinstance(cr['result'], list) and cr['result']:
            lead = cr['result'][0]

    if not lead:
        print('\nFailed to obtain lead from Odoo; aborting normalization test.')
    else:
        # run the normalizer loaded from file path
        import importlib.util
        import pathlib
        mod_path = pathlib.Path(__file__).resolve().parents[1] / 'recipes' / '_normalizers' / 'CommonCustomerProfile' / 'normalize_customer_profile.py'
        spec = importlib.util.spec_from_file_location('normalize_customer_profile', str(mod_path))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        normalize_run = module.run
        norm = normalize_run({'odoo_lead': lead})
        print('\nNORMALIZED RESULT:')
        print(json.dumps(norm, indent=2))
