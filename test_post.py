import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

req = urllib.request.Request("http://35.237.49.45:8090/api/collections/notes/records", 
    data=json.dumps({"title": "py title", "content": "py content"}).encode('utf-8'),
    headers={"Content-Type": "application/json"}
)
try:
    with urllib.request.urlopen(req, context=ctx) as response:
        print(response.read().decode('utf-8'))
except urllib.error.HTTPError as e:
    print(e.code, e.read().decode('utf-8'))
