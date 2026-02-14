# Remaining Implementation Tasks

## Completed ✅
1. **Issue #8**: Notes now open in full screen ✅
2. **Issue #2**: Gold price service now has debug logging with method tracking ✅
3. **Issue #3**: Added old inspection method as second fallback ✅

## Remaining Tasks 🔄

### Issue #1: Duplicate Notification Bug
**Problem**: Notification triggers twice when clicked, but not when ignored
**Status**: NEEDS INVESTIGATION
**Files to check**:
- `lib/services/notification_service.dart`
- `lib/screens/home_screen.dart`
**Likely cause**: Notification click handler might be rescheduling the notification
**Solution**: Need to find where notifications are scheduled and ensure they're cancelled when clicked

### Issue #4: Gold Price UI Improvements
**Changes needed**:
1. Change price color from yellow to dark color matching background
2. Green color for price increase
3. Red color for price decrease
4. Remove "- No Change" text

**Files to modify**:
- `lib/screens/gold_screen.dart`

**Implementation**:
```dart
// In gold_screen.dart
Color getPriceChangeColor(double? difference) {
  if (difference == null || difference == 0) return Colors.grey;
  return difference > 0 ? Colors.green : Colors.red;
}

// Price display
Text(
  '₹${_latestPrice?.price22k.toStringAsFixed(0)}',
  style: TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.bold,
    color: Theme.of(context).colorScheme.onSurface, // Dark color
  ),
)

// Change display
if (difference != 0)
  Text(
    '${difference > 0 ? '+' : ''}₹${difference.toStringAsFixed(0)}',
    style: TextStyle(
      color: getPriceChangeColor(difference),
      fontWeight: FontWeight.bold,
    ),
  )
```

### Issue #5: Gold Price Refresh Logic
**Problem**: Refresh button adds new row even if price hasn't changed
**Expected**: Update existing row if price unchanged on same day

**Files to modify**:
- `lib/screens/gold_screen.dart`
- `lib/services/storage_service.dart`

**Implementation**:
```dart
// In gold_screen.dart _refreshPrice method
Future<void> _refreshPrice() async {
  final result = await _goldService.fetchCurrentGoldPrice();
  final newPrice = result['price'] as GoldPrice?;
  
  if (newPrice != null) {
    final latest = await _storage.getLatestGoldPrice();
    
    // Check if price changed
    if (latest != null && 
        latest.date == newPrice.date &&
        (newPrice.price22k - latest.price22k).abs() < 1.0) {
      // Price hasn't changed, just update timestamp
      await _storage.updateGoldPriceTimestamp(newPrice);
    } else {
      // Price changed or new day, save new row
      await _storage.saveGoldPrice(newPrice);
    }
  }
}
```

### Issue #6: Data Persistence
**Status**: ALREADY IMPLEMENTED ✅
**Note**: Data already persists using SQLite. The AppInitService reschedules notifications on app restart.

### Issue #7: Multi-Month Shift Roster
**Changes needed**:
1. Support storing multiple months of rosters
2. Add "This Month" and "Next Month" toggle buttons
3. Allow updating each roster separately

**Files to modify**:
- `lib/screens/my_shifts_screen.dart`
- `lib/services/storage_service.dart`
- Database schema (add month column to shifts table)

**Database changes**:
```sql
ALTER TABLE shifts ADD COLUMN roster_month TEXT;
ALTER TABLE shift_metadata ADD COLUMN roster_month TEXT;
```

**UI Implementation**:
```dart
// Add toggle buttons above statistics
Row(
  children: [
    SegmentedButton(
      segments: [
        ButtonSegment(value: 'current', label: Text('This Month')),
        ButtonSegment(value: 'next', label: Text('Next Month')),
      ],
      selected: {_selectedMonth},
      onSelectionChanged: (Set<String> selection) {
        setState(() {
          _selectedMonth = selection.first;
          _loadShifts(_selectedMonth);
        });
      },
    ),
  ],
)
```

## Priority Order
1. **HIGH**: Issue #1 (Duplicate notifications) - Affects user experience
2. **HIGH**: Issue #5 (Refresh logic) - Data integrity issue
3. **MEDIUM**: Issue #4 (UI colors) - Visual improvement
4. **MEDIUM**: Issue #7 (Multi-month roster) - Feature enhancement
5. **LOW**: Issues #2, #3 (Debug logging) - Already completed ✅
6. **LOW**: Issue #6 (Data persistence) - Already working ✅
7. **LOW**: Issue #8 (Notes full screen) - Already completed ✅

## Testing Checklist
- [ ] Notes open in full screen
- [ ] Gold price debug logging shows method used
- [ ] Duplicate notification bug fixed
- [ ] Gold price colors updated (dark price, green/red changes)
- [ ] Refresh doesn't add duplicate rows
- [ ] Multi-month roster support
- [ ] Data persists across app restarts

## Notes
- Some changes require database migrations
- Notification bug needs investigation before implementation
- Multi-month feature is a significant enhancement
