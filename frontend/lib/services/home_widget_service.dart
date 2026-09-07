import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/shift.dart';
import 'log_service.dart';

class HomeWidgetService {
  static final HomeWidgetService _instance = HomeWidgetService._internal();
  factory HomeWidgetService() => _instance;
  HomeWidgetService._internal();

  StreamSubscription? _accountsSub;
  StreamSubscription? _smsTxSub;
  StreamSubscription? _manualTxSub;
  StreamSubscription? _shiftMonthSub;
  StreamSubscription? _dailyShiftsSub;

  /// Starts real-time Firestore listeners on accounts & transactions so the
  /// Home Widget updates immediately whenever bank balance or transactions change.
  void startFinanceWidgetLiveSync() {
    if (kIsWeb) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _accountsSub?.cancel();
    _accountsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('finance_accounts')
        .snapshots()
        .listen((_) {
      syncFinanceWidget();
    }, onError: (e) {
      LogService().error('Error in finance_accounts stream for widget', e);
    });

    _smsTxSub?.cancel();
    _smsTxSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sms_transactions')
        .snapshots()
        .listen((_) {
      syncFinanceWidget();
    }, onError: (e) {
      LogService().error('Error in sms_transactions stream for widget', e);
    });

    _manualTxSub?.cancel();
    _manualTxSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('finance_transactions')
        .snapshots()
        .listen((_) {
      syncFinanceWidget();
    }, onError: (e) {
      LogService().error('Error in finance_transactions stream for widget', e);
    });
  }

  void stopFinanceWidgetLiveSync() {
    _accountsSub?.cancel();
    _smsTxSub?.cancel();
    _manualTxSub?.cancel();
  }

  /// Starts real-time Firestore listeners on shifts so the
  /// Shift widgets update immediately whenever a roster is uploaded or modified.
  void startShiftWidgetLiveSync() {
    if (kIsWeb) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final currentRosterMonth = DateFormat('yyyy-MM').format(now);

    _shiftMonthSub?.cancel();
    _shiftMonthSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('shifts')
        .snapshots()
        .listen((_) {
      syncShiftWidgets();
    }, onError: (e) {
      LogService().error('Error in shifts collection stream for widget', e);
    });

    _dailyShiftsSub?.cancel();
    _dailyShiftsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('shifts')
        .doc(currentRosterMonth)
        .collection('daily_shifts')
        .snapshots()
        .listen((_) {
      syncShiftWidgets();
    }, onError: (e) {
      LogService().error('Error in daily_shifts collection stream for widget', e);
    });
  }

  void stopShiftWidgetLiveSync() {
    _shiftMonthSub?.cancel();
    _dailyShiftsSub?.cancel();
  }

  /// Updates the Gold Rates Home Screen Widget (22K Per Gram & 22K 8g Sovereign)
  Future<void> updateGoldWidget({
    required double rate22k,
    required double changeToday,
    DateTime? updatedAt,
  }) async {
    if (kIsWeb) return;
    try {
      final currencyFormat = NumberFormat('#,##,##0');
      final double sovereign22k = rate22k * 8;

      final String changeText = changeToday > 0
          ? '▲ +₹${currencyFormat.format(changeToday.abs())}'
          : (changeToday < 0
              ? '▼ -₹${currencyFormat.format(changeToday.abs())}'
              : 'Live Rate');

      final updateDate = updatedAt ?? DateTime.now();
      final String timeText = 'Updated ${DateFormat('hh:mm a').format(updateDate)}';

      await HomeWidget.saveWidgetData<String>('gold_22k_gram', '₹${currencyFormat.format(rate22k)}/g');
      await HomeWidget.saveWidgetData<String>('gold_22k_sovereign', '₹${currencyFormat.format(sovereign22k)} (8g)');
      await HomeWidget.saveWidgetData<String>('gold_change', changeText);
      await HomeWidget.saveWidgetData<String>('gold_time', timeText);

      await HomeWidget.updateWidget(
        name: 'GoldWidgetProvider',
        androidName: 'GoldWidgetProvider',
        qualifiedAndroidName: 'com.remindbuddy.remindbuddy.GoldWidgetProvider',
      );
    } catch (e) {
      LogService().error('Failed to update GoldWidget', e);
    }
  }

  /// Updates the Bank Balance & Cashflow Home Screen Widget
  Future<void> updateFinanceWidget({
    required double totalBalance,
    required double todayIn,
    required double todayOut,
    required List<Map<String, dynamic>> accounts,
  }) async {
    if (kIsWeb) return;
    try {
      final currencyFormat = NumberFormat('#,##,##0');
      final String balanceText = 'Total: ₹${currencyFormat.format(totalBalance)}';
      final String inText = '+₹${currencyFormat.format(todayIn)}';
      final String outText = '-₹${currencyFormat.format(todayOut)}';
      final String timeText = 'Synced ${DateFormat('hh:mm a').format(DateTime.now())}';

      await HomeWidget.saveWidgetData<String>('finance_balance', balanceText);
      await HomeWidget.saveWidgetData<String>('finance_in', inText);
      await HomeWidget.saveWidgetData<String>('finance_out', outText);
      await HomeWidget.saveWidgetData<String>('finance_time', timeText);

      // Save each connected account up to 4 accounts
      for (int i = 0; i < 4; i++) {
        if (i < accounts.length) {
          final a = accounts[i];
          final name = (a['name'] ?? a['accountName'] ?? a['bankName'] ?? 'Bank Account').toString();
          final bal = (a['currentBalance'] as num?)?.toDouble() ?? 
                      (a['balance'] as num?)?.toDouble() ?? 
                      (a['initialBalance'] as num?)?.toDouble() ?? 0.0;
          await HomeWidget.saveWidgetData<String>('finance_acc${i + 1}_name', name);
          await HomeWidget.saveWidgetData<String>('finance_acc${i + 1}_bal', '₹${currencyFormat.format(bal)}');
        } else {
          await HomeWidget.saveWidgetData<String>('finance_acc${i + 1}_name', '');
          await HomeWidget.saveWidgetData<String>('finance_acc${i + 1}_bal', '');
        }
      }

      await HomeWidget.updateWidget(
        name: 'FinanceWidgetProvider',
        androidName: 'FinanceWidgetProvider',
        qualifiedAndroidName: 'com.remindbuddy.remindbuddy.FinanceWidgetProvider',
      );
    } catch (e) {
      LogService().error('Failed to update FinanceWidget', e);
    }
  }

  /// Updates the Work Shift & Roster Home Screen Widget
  Future<void> updateShiftWidget({
    required String todayShiftName,
    required String todayShiftTime,
    required String tomorrowShiftName,
  }) async {
    if (kIsWeb) return;
    try {
      final String dateText = 'Today (${DateFormat('dd MMM').format(DateTime.now())})';

      await HomeWidget.saveWidgetData<String>('shift_name', todayShiftName);
      await HomeWidget.saveWidgetData<String>('shift_time', todayShiftTime);
      await HomeWidget.saveWidgetData<String>('shift_tomorrow', tomorrowShiftName);
      await HomeWidget.saveWidgetData<String>('shift_date', dateText);

      await HomeWidget.updateWidget(
        name: 'ShiftWidgetProvider',
        androidName: 'ShiftWidgetProvider',
        qualifiedAndroidName: 'com.remindbuddy.remindbuddy.ShiftWidgetProvider',
      );
    } catch (e) {
      LogService().error('Failed to update ShiftWidget', e);
    }
  }

  /// Syncs Bank Balance & Today's In/Out immediately to the Home Widget
  Future<void> syncFinanceWidget() async {
    if (kIsWeb) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final accountsSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('finance_accounts')
          .get(const GetOptions(source: Source.serverAndCache));

      final List<Map<String, dynamic>> accountsList = [];
      double totalBalance = 0.0;

      for (var d in accountsSnap.docs) {
        final data = d.data();
        final name = (data['name'] ?? data['accountName'] ?? data['bankName'] ?? 'Bank Account').toString();
        final bal = (data['currentBalance'] as num?)?.toDouble() ?? 
                    (data['balance'] as num?)?.toDouble() ?? 
                    (data['initialBalance'] as num?)?.toDouble() ?? 0.0;
        totalBalance += bal;
        accountsList.add({'name': name, 'balance': bal});
      }

      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

      double todayIn = 0.0;
      double todayOut = 0.0;

      // Query only today's manual transactions
      QuerySnapshot manualTxSnap;
      try {
        manualTxSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('finance_transactions')
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
            .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(todayEnd))
            .get(const GetOptions(source: Source.serverAndCache));
      } catch (_) {
        manualTxSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('finance_transactions')
            .get(const GetOptions(source: Source.serverAndCache));
      }

      for (final doc in manualTxSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final ts = data['timestamp'] ?? data['date'];
        DateTime? dt;
        if (ts is Timestamp) {
          dt = ts.toDate();
        } else if (ts is String) {
          dt = DateTime.tryParse(ts);
        } else if (ts is int) {
          dt = DateTime.fromMillisecondsSinceEpoch(ts);
        }

        if (dt != null && DateFormat('yyyy-MM-dd').format(dt) == todayStr) {
          final amt = (data['amount'] as num? ?? 0.0).toDouble();
          final type = (data['type'] ?? '').toString().toLowerCase();
          if (type == 'income' || type == 'credit' || type == 'received' || type == 'credited') {
            todayIn += amt;
          } else if (type == 'expense' || type == 'debit' || type == 'sent' || type == 'debited') {
            todayOut += amt;
          }
        }
      }

      // Query today's SMS transactions
      QuerySnapshot smsTxSnap;
      try {
        smsTxSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('sms_transactions')
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
            .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(todayEnd))
            .get(const GetOptions(source: Source.serverAndCache));
      } catch (_) {
        smsTxSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('sms_transactions')
            .get(const GetOptions(source: Source.serverAndCache));
      }

      for (final doc in smsTxSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final cat = (data['category'] ?? '').toString();
        if (cat.contains('Ignored') || cat == 'Self Transfer') continue;

        DateTime? dt;
        final ts = data['timestamp'] ?? data['date'];
        if (ts is Timestamp) {
          dt = ts.toDate();
        } else if (ts is String) {
          dt = DateTime.tryParse(ts);
        } else if (ts is int) {
          dt = DateTime.fromMillisecondsSinceEpoch(ts);
        }

        if (dt != null && DateFormat('yyyy-MM-dd').format(dt) == todayStr) {
          final amt = (data['amount'] as num? ?? 0.0).toDouble();
          final type = (data['type'] ?? '').toString().toLowerCase();
          if (type == 'credit' || type == 'income' || type == 'received' || type == 'credited') {
            todayIn += amt;
          } else if (type == 'debit' || type == 'expense' || type == 'sent' || type == 'debited') {
            todayOut += amt;
          }
        }
      }

      await updateFinanceWidget(
        totalBalance: totalBalance,
        todayIn: todayIn,
        todayOut: todayOut,
        accounts: accountsList,
      );
    } catch (e) {
      LogService().error('Error in syncFinanceWidget', e);
    }
  }

  /// Syncs current shifts immediately to both ShiftWidget and ShiftCalendarWidget
  Future<void> syncShiftWidgets() async {
    if (kIsWeb) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final currentRosterMonth = DateFormat('yyyy-MM').format(now);

      // 1. Fetch Today's Shift
      final todayShiftDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('shifts')
          .doc(currentRosterMonth)
          .collection('daily_shifts')
          .doc(todayStr)
          .get(const GetOptions(source: Source.serverAndCache));

      String todayName = 'Week Off 🏖️';
      String todayTime = 'Off Duty';

      if (todayShiftDoc.exists) {
        final data = todayShiftDoc.data() ?? {};
        final rawType = (data['shift_type'] ?? data['shiftType'] ?? '').toString().toLowerCase();
        if (!rawType.contains('off') && rawType.isNotEmpty) {
          todayName = '${rawType.toUpperCase().replaceAll('_', ' ')} SHIFT';
          final start = (data['start_time'] ?? data['startTime'] ?? '').toString();
          final end = (data['end_time'] ?? data['endTime'] ?? '').toString();
          if (start.isNotEmpty && end.isNotEmpty) {
            todayTime = '$start - $end';
          } else {
            todayTime = 'Scheduled Shift';
          }
        }
      }

      // 2. Fetch Tomorrow's Shift
      final tomorrow = now.add(const Duration(days: 1));
      final tomorrowMonth = DateFormat('yyyy-MM').format(tomorrow);
      final tomorrowStr = DateFormat('yyyy-MM-dd').format(tomorrow);

      final tomorrowShiftDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('shifts')
          .doc(tomorrowMonth)
          .collection('daily_shifts')
          .doc(tomorrowStr)
          .get(const GetOptions(source: Source.serverAndCache));

      String tomorrowName = 'Tomorrow: Week Off';
      if (tomorrowShiftDoc.exists) {
        final data = tomorrowShiftDoc.data() ?? {};
        final rawType = (data['shift_type'] ?? data['shiftType'] ?? '').toString().toLowerCase();
        if (!rawType.contains('off') && rawType.isNotEmpty) {
          final title = rawType.toUpperCase().replaceAll('_', ' ');
          final start = (data['start_time'] ?? data['startTime'] ?? '').toString();
          tomorrowName = start.isNotEmpty ? 'Tomorrow: $title ($start)' : 'Tomorrow: $title';
        }
      }

      // Update Single Shift Widget
      await updateShiftWidget(
        todayShiftName: todayName,
        todayShiftTime: todayTime,
        tomorrowShiftName: tomorrowName,
      );

      // 3. Fetch Full Month's Shifts for Shift Calendar Widget
      final monthShiftsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('shifts')
          .doc(currentRosterMonth)
          .collection('daily_shifts')
          .get(const GetOptions(source: Source.serverAndCache));

      List<Shift> monthShifts = [];
      if (monthShiftsSnapshot.docs.isNotEmpty) {
        monthShifts = monthShiftsSnapshot.docs.map((d) {
          return Shift.fromJson(d.data());
        }).toList();
      } else {
        // Fallback: check if the month document itself has raw_json
        final monthDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('shifts')
            .doc(currentRosterMonth)
            .get(const GetOptions(source: Source.serverAndCache));
        if (monthDoc.exists && monthDoc.data()?['raw_json'] != null) {
          try {
            final raw = jsonDecode(monthDoc.data()!['raw_json'].toString());
            if (raw is Map && raw['shifts'] is List) {
              monthShifts = (raw['shifts'] as List)
                  .map((s) => Shift.fromJson(s as Map))
                  .toList();
            }
          } catch (_) {}
        }
      }

      // Always update calendar widget, even if monthShifts is empty (clean monthly view)
      await updateShiftCalendarWidget(
        shifts: monthShifts,
        monthDate: now,
      );
    } catch (e) {
      LogService().error('Error in syncShiftWidgets', e);
    }
  }

  /// Pulls the latest live state from Firestore & caches, pushing updates to all widgets
  Future<void> syncAllWidgets() async {
    if (kIsWeb) return;

    // 1. Sync Gold Widget
    try {
      final goldSnap = await FirebaseFirestore.instance
          .collection('gold_prices')
          .orderBy('timestamp', descending: true)
          .limit(2)
          .get();

      if (goldSnap.docs.isNotEmpty) {
        final latest = goldSnap.docs.first.data();
        final double rate22k = (latest['rate22k'] as num?)?.toDouble() ?? 
                               (latest['price'] as num?)?.toDouble() ?? 
                               (latest['rate24k'] as num?)?.toDouble() ?? 7200.0;

        DateTime? updateTime;
        final ts = latest['timestamp'];
        if (ts is Timestamp) {
          updateTime = ts.toDate();
        } else if (ts is String) {
          updateTime = DateTime.tryParse(ts);
        }

        double change = 0.0;
        if (goldSnap.docs.length > 1) {
          final prev = goldSnap.docs[1].data();
          final double prev22k = (prev['rate22k'] as num?)?.toDouble() ?? 
                                 (prev['price'] as num?)?.toDouble() ?? rate22k;
          change = rate22k - prev22k;
        }

        await updateGoldWidget(
          rate22k: rate22k,
          changeToday: change,
          updatedAt: updateTime,
        );
      }
    } catch (e) {
      LogService().error('Error syncing Gold Widget in syncAllWidgets', e);
    }

    // 2. Sync Finance Widget
    try {
      await syncFinanceWidget();
    } catch (e) {
      LogService().error('Error syncing Finance Widget in syncAllWidgets', e);
    }

    // 3. Sync Shift Widgets
    try {
      await syncShiftWidgets();
    } catch (e) {
      LogService().error('Error syncing Shift Widgets in syncAllWidgets', e);
    }
  }

  /// Updates the full Monthly Shift Calendar Home Screen Widget
  Future<void> updateShiftCalendarWidget({
    required List<Shift> shifts,
    required DateTime monthDate,
  }) async {
    if (kIsWeb) return;
    try {
      final monthTitle = DateFormat('MMMM yyyy').format(monthDate);
      await HomeWidget.saveWidgetData<String>('shift_calendar_month', monthTitle);

      // Save a compact JSON map of date -> shiftType for native Android Kotlin fallback
      final Map<String, String> shiftsJsonMap = {};
      for (final s in shifts) {
        shiftsJsonMap[s.date] = s.shiftType;
      }
      await HomeWidget.saveWidgetData<String>('shift_calendar_shifts_json', jsonEncode(shiftsJsonMap));

      // Render the calendar directly to a 420x420 PNG file via Skia/Impeller Canvas
      final imagePath = await _renderShiftCalendarToPng(shifts: shifts, monthDate: monthDate);
      if (imagePath != null) {
        await HomeWidget.saveWidgetData<String>('shift_calendar_image_path', imagePath);
      }

      await HomeWidget.updateWidget(
        name: 'ShiftCalendarWidgetProvider',
        androidName: 'ShiftCalendarWidgetProvider',
        qualifiedAndroidName: 'com.remindbuddy.remindbuddy.ShiftCalendarWidgetProvider',
      );
    } catch (e) {
      LogService().error('Failed to update ShiftCalendarWidget', e);
    }
  }

  Future<String?> _renderShiftCalendarToPng({
    required List<Shift> shifts,
    required DateTime monthDate,
  }) async {
    try {
      const double size = 420.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

      final year = monthDate.year;
      final month = monthDate.month;
      final daysInMonth = DateTime(year, month + 1, 0).day;
      final firstWeekday = DateTime(year, month, 1).weekday % 7; // 0 for Sunday
      final today = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(today);

      final Map<String, Shift> shiftByDate = {
        for (var s in shifts) s.date: s,
      };

      // 1. Background Card
      final bgPaint = Paint()..color = const Color(0xFF0F141C);
      final bgRect = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, size, size), const Radius.circular(20));
      canvas.drawRRect(bgRect, bgPaint);

      // Card Border
      final borderPaint = Paint()
        ..color = const Color(0xFF1E293B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRRect(bgRect, borderPaint);

      // 2. Weekday Headers
      const weekdays = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
      const double marginX = 14.0;
      const double gridWidth = size - (2 * marginX);
      const double colWidth = gridWidth / 7.0;

      for (int i = 0; i < 7; i++) {
        final cx = marginX + (i * colWidth) + (colWidth / 2.0);
        _drawCanvasText(
          canvas: canvas,
          text: weekdays[i],
          x: cx,
          y: 10,
          align: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        );
      }

      // 3. Days Grid
      const double gridTop = 36.0;
      const double gridBottom = 384.0;
      const double gridHeight = gridBottom - gridTop;
      const double spacing = 4.0;
      const double cellW = (gridWidth - (6 * spacing)) / 7.0;
      final int numRows = ((firstWeekday + daysInMonth + 6) ~/ 7).clamp(5, 6);
      final double cellH = (gridHeight - ((numRows - 1) * spacing)) / numRows;

      final cellBgPaint = Paint()..color = const Color(0xFF1E2638);
      final cellBorderPaint = Paint()
        ..color = const Color(0xFF263248)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      final todayBorderPaint = Paint()
        ..color = const Color(0xFF38BDF8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      for (int day = 1; day <= daysInMonth; day++) {
        final slotIndex = (day - 1) + firstWeekday;
        final col = slotIndex % 7;
        final row = slotIndex ~/ 7;

        final cellLeft = marginX + (col * (cellW + spacing));
        final cellTop = gridTop + (row * (cellH + spacing));
        final cellRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(cellLeft, cellTop, cellW, cellH),
          const Radius.circular(6),
        );

        final dateStr = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        final isToday = dateStr == todayStr;
        final shift = shiftByDate[dateStr];

        canvas.drawRRect(cellRect, cellBgPaint);
        canvas.drawRRect(cellRect, isToday ? todayBorderPaint : cellBorderPaint);

        // Day Number
        _drawCanvasText(
          canvas: canvas,
          text: '$day',
          x: cellLeft + (cellW / 2.0),
          y: cellTop + 4,
          align: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isToday ? FontWeight.w900 : FontWeight.bold,
            color: isToday ? const Color(0xFF38BDF8) : const Color(0xFFE2E8F0),
          ),
        );

        // Shift Badge
        if (shift != null) {
          Color badgeColor = const Color(0xFF6366F1);
          String badgeText = shift.shiftType.isNotEmpty ? shift.shiftType[0].toUpperCase() : '';
          final lower = shift.shiftType.toLowerCase();
          if (lower.contains('morning') || lower == 'm') {
            badgeColor = const Color(0xFFF59E0B);
            badgeText = 'M';
          } else if (lower.contains('afternoon') || lower.contains('evening') || lower == 'a') {
            badgeColor = const Color(0xFF06B6D4);
            badgeText = 'A';
          } else if (lower.contains('night') || lower == 'n') {
            badgeColor = const Color(0xFF8B5CF6);
            badgeText = 'N';
          } else if (lower.contains('off') || lower.contains('leave') || lower == 'wo') {
            badgeColor = const Color(0xFF10B981);
            badgeText = 'OFF';
          } else if (lower.contains('general') || lower == 'g') {
            badgeColor = const Color(0xFF3B82F6);
            badgeText = 'G';
          }

          const double badgeH = 15.0;
          const double badgeW = cellW - 6.0;
          final double badgeLeft = cellLeft + 3.0;
          final double badgeTop = cellTop + cellH - badgeH - 3.0;

          final badgeRect = RRect.fromRectAndRadius(
            Rect.fromLTWH(badgeLeft, badgeTop, badgeW, badgeH),
            const Radius.circular(4),
          );
          final badgePaint = Paint()..color = badgeColor;
          canvas.drawRRect(badgeRect, badgePaint);

          _drawCanvasText(
            canvas: canvas,
            text: badgeText,
            x: badgeLeft + (badgeW / 2.0),
            y: badgeTop + 1,
            align: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          );
        }
      }

      // 4. Legend
      const double legendY = 396.0;
      const legendItems = [
        {'color': Color(0xFFF59E0B), 'label': 'M: Morn'},
        {'color': Color(0xFF06B6D4), 'label': 'A: Aft'},
        {'color': Color(0xFF8B5CF6), 'label': 'N: Night'},
        {'color': Color(0xFF10B981), 'label': 'OFF'},
      ];

      final double itemSpacing = gridWidth / legendItems.length;
      for (int i = 0; i < legendItems.length; i++) {
        final item = legendItems[i];
        final startX = marginX + (i * itemSpacing) + 6.0;

        final dotPaint = Paint()..color = item['color'] as Color;
        canvas.drawCircle(Offset(startX, legendY + 6), 4, dotPaint);

        _drawCanvasText(
          canvas: canvas,
          text: item['label'] as String,
          x: startX + 8,
          y: legendY,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        );
      }

      final picture = recorder.endRecording();
      final img = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final buffer = byteData.buffer.asUint8List();
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/shift_calendar_widget.png');
        await file.writeAsBytes(buffer, flush: true);
        return file.path;
      }
    } catch (e) {
      LogService().error('Error rendering shift calendar to PNG', e);
    }
    return null;
  }

  void _drawCanvasText({
    required Canvas canvas,
    required String text,
    required double x,
    required double y,
    required TextStyle style,
    TextAlign align = TextAlign.left,
  }) {
    final textSpan = TextSpan(text: text, style: style);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: ui.TextDirection.ltr,
      textAlign: align,
    );
    textPainter.layout();

    double dx = x;
    if (align == TextAlign.right) {
      dx = x - textPainter.width;
    } else if (align == TextAlign.center) {
      dx = x - (textPainter.width / 2.0);
    }

    textPainter.paint(canvas, Offset(dx, y));
  }
}
