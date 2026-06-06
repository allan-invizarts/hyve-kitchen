import json
import random
import urllib.request

base_url='http://localhost:8069'
url=f'{base_url}/jsonrpc'

def rpc(service, method, *args):
    payload={'jsonrpc':'2.0','method':'call','id':random.randint(1,999999999),'params':{'service':service,'method':method,'args':list(args)}}
    req=urllib.request.Request(url=url,data=json.dumps(payload).encode('utf-8'),headers={'Content-Type':'application/json'},method='POST')
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.load(resp)

for db in ['hyve_kitchen','odoo']:
    for user,pwd in [('admin','admin'),('test_recipe_user@example.com','Test12345!')]:
        try:
            r=rpc('common','login',db,user,pwd)
            print(f'{db} {user}:', r)
        except Exception as exc:
            print(f'{db} {user} EXC:', exc)
