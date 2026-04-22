import requests
from bs4 import BeautifulSoup

url = "https://www.goodreturns.in/gold-rates/chennai.html"

print("--- Method 1: Standard Python Requests Library ---")
try:
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    }
    res = requests.get(url, headers=headers, timeout=10)
    print(f"Status Code: {res.status_code}")
    if res.status_code == 200:
        soup = BeautifulSoup(res.text, 'html.parser')
        price_elem = soup.find(id="22K-price")
        if price_elem:
            print("Target Text found:", price_elem.text.strip())
        else:
            print("ID #22K-price not found in standard request HTML.")
    else:
        print("Blocked. Could not fetch HTML.")
except Exception as e:
    print("Requests Error:", e)
