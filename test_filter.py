import urllib.request
import urllib.parse
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

with open('token.txt', 'r') as f:
    token = f.read().strip()

filter_query = urllib.parse.quote('month_year="2026-02"')
req = urllib.request.Request(f"http://35.237.49.45:8090/api/collections/shifts_data/records?filter={filter_query}", 
    headers={"Authorization": token}
)
try:
    with urllib.request.urlopen(req, context=ctx) as response:
        print(response.read().decode('utf-8'))
except urllib.error.HTTPError as e:
    print(e.code, e.read().decode('utf-8'))
