#!/bin/bash

# Gold Price Feature Test Script
# This script helps test the gold price fetching feature

echo "🧪 RemindBuddy - Gold Price Feature Test"
echo "========================================"
echo ""

# Check if we're in the frontend directory
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Error: Please run this script from the frontend directory"
    exit 1
fi

echo "1️⃣  Running Flutter analyze..."
flutter analyze --no-fatal-infos --no-fatal-warnings
if [ $? -eq 0 ]; then
    echo "✅ Analysis passed (ignoring warnings)"
else
    echo "⚠️  Analysis found issues (check above)"
fi

echo ""
echo "2️⃣  Checking dependencies..."
flutter pub get > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ Dependencies OK"
else
    echo "❌ Dependency issues"
    exit 1
fi

echo ""
echo "3️⃣  Verifying key files exist..."
files=(
    "lib/services/gold_scheduler_service.dart"
    "lib/services/gold_price_service.dart"
    "lib/screens/gold_screen.dart"
    "lib/models/gold_price.dart"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✅ $file"
    else
        echo "  ❌ $file (missing)"
    fi
done

echo ""
echo "4️⃣  Checking Android configuration..."
if grep -q "android_alarm_manager_plus" "pubspec.yaml"; then
    echo "  ✅ android_alarm_manager_plus in pubspec.yaml"
else
    echo "  ❌ android_alarm_manager_plus missing"
fi

if grep -q "syncfusion_flutter_charts" "pubspec.yaml"; then
    echo "  ✅ syncfusion_flutter_charts in pubspec.yaml"
else
    echo "  ❌ syncfusion_flutter_charts missing"
fi

if grep -q "AlarmService" "android/app/src/main/AndroidManifest.xml"; then
    echo "  ✅ AlarmService in AndroidManifest.xml"
else
    echo "  ❌ AlarmService missing from AndroidManifest.xml"
fi

echo ""
echo "========================================"
echo "📋 Test Summary"
echo "========================================"
echo ""
echo "To test the gold price feature:"
echo ""
echo "1. Build and run the app:"
echo "   flutter run"
echo ""
echo "2. Navigate to the Gold tab"
echo ""
echo "3. Tap the refresh button to test manual fetch"
echo ""
echo "4. Check the schedule info at the bottom:"
echo "   - 11 AM IST: Daily update (always saved)"
echo "   - 7 PM IST: Update if price changed"
echo ""
echo "5. To clear data and test fresh:"
echo "   - Tap the trash icon"
echo "   - Confirm deletion"
echo "   - Tap refresh to fetch new data"
echo ""
echo "6. Monitor logs for:"
echo "   - '🔍 Fetching gold price...'"
echo "   - '💰 Parsed 22K price: ₹...'"
echo "   - '✅ Gold price scheduler initialized'"
echo ""
echo "========================================"
