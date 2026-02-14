# Gold Price Checker

This is a standalone Node.js script to test the gold price extraction logic used in the RemindBuddy app basically in the `gold_price_service.dart`.

It uses **Puppeteer** (headless Chrome) to visit the target website and run the exact same JavaScript extraction methods as the mobile app.

## Setup

1. Make sure you have Node.js installed.
2. Open this folder in a terminal:
   ```bash
   cd Gold_Price_Checking
   ```
3. Install dependencies:
   ```bash
   npm install
   ```

## Usage

Run the checker script:

```bash
node check_price.js
```

## What it does

The script will:
1. Launch a headless browser
2. Navigate to `https://www.goodreturns.in/gold-rates/chennai.html`
3. Execute **ALL 4** fallback methods sequentially:
   - **Method 1 (XPath)**: Tries to find the exact price element
   - **Method 2 (Inspection)**: Scans for containers with "price" or "rate" classes
   - **Method 3 (Heading Search)**: Looks for "Today's Gold Rate" heading
   - **Method 4 (Generic Search)**: Scans all elements for "₹" symbol and price pattern

It will then print a JSON report showing the output of each method. This helps verify if the fallbacks are working correctly even if the primary method fails.
