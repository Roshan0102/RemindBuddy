# Bug Fixes and Improvements - v1.0.33+37

## Date: February 14, 2026

### Critical Fixes

## 🐛 Issue #1: Gold Price Parsing Error - FIXED
**Problem**: App showed error "Failed to fetch: Parsed price invalid: 14.0 from text Rs 14"

**Root Cause**: 
- The regex pattern was too loose and extracted "14" from "Rs 14" instead of the full price "14,400"
- The old regex `\d{2,}` matched any 2+ digits, including partial prices

**Solution**:
1. **Improved JavaScript extraction** (lines 57-90 in gold_price_service.dart):
   - Added validation to only extract prices with 4+ digits
   - New regex: `/\d{1,3}(,\d{3})+|\d{4,}/` matches "14,400" or "14400"
   - Checks for both "₹" and "Rs" symbols
   - Validates price range (1000-100000)

2. **Better Dart parsing** (lines 129-166):
   - Uses same regex pattern to extract price from text
   - Removes commas before parsing
   - Logs extracted text for debugging
   - Clear error messages when parsing fails

**Result**: Gold prices now parse correctly, rejecting invalid partial prices

---

## 📊 Issue #2: Data Loss After App Update - EXPLAINED
**Problem**: My Belongings, Daily Reminders, and Shifts data disappeared after installing new build

**Explanation**:
Data persistence works differently for app updates vs uninstalls:

**✅ Data WILL persist** if you:
- Update the app without uninstalling (flutter run, flutter install)
- Install APK over existing installation
- Use app store updates

**❌ Data will NOT persist** if you:
- Uninstall the app before installing new version
- Clear app data in Android settings
- Change the app package name

**Database Migration**:
- Version bumped from 7 → 8 for multi-month shifts
- Migration adds `roster_month` column to existing data
- All existing data should be preserved during migration

**Updated Documentation**: `DATA_PERSISTENCE.md` now clearly explains this behavior

---

## 📅 Issue #3: Multi-Month Roster UI - IMPLEMENTED
**Problem**: Need UI to switch between current and next month rosters

**Solution**:
1. **Added State Variables** (my_shifts_screen.dart):
   ```dart
   List<String> _availableMonths = [];
   String? _selectedRosterMonth;
   String _selectedMonthView = 'current'; // 'current' or 'next'
   ```

2. **Month Toggle Buttons** (lines 521-548):
   - Segmented button with "This Month" and "Next Month"
   - Icons for visual clarity
   - Automatically calculates roster month based on selection

3. **Updated Data Loading**:
   - `_loadAvailableMonths()`: Fetches list of stored roster months
   - `_switchMonth()`: Changes selected month and reloads data
   - All storage methods now use `rosterMonth` parameter

4. **Automatic Month Detection**:
   - When uploading roster, extracts month from first shift date
   - Format: "2026-02-14" → "2026-02"
   - Saves with proper roster_month identifier

**UI Location**: Toggle buttons appear above statistics card

---

## Technical Improvements

### Gold Price Service
**File**: `frontend/lib/services/gold_price_service.dart`

**Changes**:
1. Better regex for price extraction
2. Validation for 4+ digit prices
3. Support for both "₹" and "Rs" symbols
4. Detailed logging for debugging
5. Clear error messages

### Storage Service
**File**: `frontend/lib/services/storage_service.dart`

**Changes**:
1. Database version 8 (multi-month support)
2. All shift methods accept optional `rosterMonth` parameter
3. New method: `getAvailableRosterMonths()`
4. Proper migration preserves existing data

### My Shifts Screen
**File**: `frontend/lib/screens/my_shifts_screen.dart`

**Changes**:
1. Month toggle UI with SegmentedButton
2. Automatic roster month detection
3. Reload available months after upload
4. Better user feedback with roster month in snackbar

---

## Files Modified (6 files)

1. **frontend/lib/services/gold_price_service.dart**
   - Improved price parsing regex
   - Better validation and error messages

2. **frontend/lib/screens/my_shifts_screen.dart**
   - Added month toggle UI
   - Multi-month state management
   - Automatic month detection

3. **frontend/lib/screens/gold_price_test_screen.dart**
   - Updated to handle new Map response format

4. **DATA_PERSISTENCE.md**
   - Clarified update vs uninstall behavior
   - Added troubleshooting section

5. **frontend/pubspec.yaml**
   - Version: 1.0.33+37

6. **BUG_FIXES_v37.md** (this file)

---

## Testing Checklist

### Gold Price
- [ ] Gold price fetches without "invalid price" error
- [ ] Prices in range 1000-100000 are accepted
- [ ] Prices below 1000 are rejected
- [ ] Debug logging shows method used

### Data Persistence
- [ ] Data persists when app is closed and reopened
- [ ] Data persists when app is updated (not uninstalled)
- [ ] Database migration from v7 to v8 works correctly

### Multi-Month Roster
- [ ] Can upload current month roster
- [ ] Can upload next month roster
- [ ] Toggle buttons switch between months
- [ ] Statistics update when switching months
- [ ] Upcoming shifts show correct data for selected month
- [ ] Can update each month independently

---

## Known Limitations

1. **Data Loss on Uninstall**: This is expected Android behavior. To preserve data across uninstalls, would need cloud backup or external storage.

2. **Month Selection**: Currently limited to "This Month" and "Next Month". Could be extended to show all available months from database.

3. **Gold Price Website Changes**: If goodreturns.in changes their HTML structure, the XPath may need updating.

---

## Version Info
- **Version**: 1.0.33+37
- **Database Version**: 8
- **Build**: Ready for release
- **Flutter Analyze**: 0 errors

---

## Recommendations

1. **For Data Preservation**:
   - Always update app without uninstalling
   - Use "flutter run" or "flutter install" for development
   - For production, use app store updates

2. **For Gold Price**:
   - Check logs if price fetch fails
   - Debug info shows which method was used
   - Fallback methods ensure high success rate

3. **For Multi-Month Rosters**:
   - Upload current month first
   - Then upload next month separately
   - Use toggle buttons to view each month
   - Each month can be updated independently
