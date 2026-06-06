import json
import random
import time
import urllib.request

base_url='http://localhost:8069'
url=f'{base_url}/jsonrpc'

def rpc(service, method, *args):
    payload={'jsonrpc':'2.0','method':'call','id':random.randint(1,999999999),'params':{'service':service,'method':method,'args':list(args)}}
    req=urllib.request.Request(url=url,data=json.dumps(payload).encode('utf-8'),headers={'Content-Type':'application/json'},method='POST')
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.load(resp)

print('Logging in as admin...')
login = rpc('common','login','odoo','admin','admin')
print(login)
uid = login.get('result')
print('uid', uid)

max_tries = 12
for i in range(max_tries):
    print('Query attempt', i+1)
    response = rpc('object','execute_kw','odoo',uid,'admin','ir.module.module','search_read',[[('name','=','stock')]],{'fields':['id','name','state','shortdesc'], 'limit':1})
    payload = response.get('result', []) if isinstance(response, dict) else response
    print(json.dumps(payload, indent=2))
    if payload and payload[0].get('state') == 'installed':
        print('Stock module installed.')
        break
    if i < max_tries - 1:
        time.sleep(5)
else:
    print('Timed out waiting for stock module to install. Current state may still be to install or pending.')
