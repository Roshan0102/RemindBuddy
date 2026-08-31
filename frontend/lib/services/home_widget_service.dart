import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'log_service.dart';

class HomeWidgetService {
  static final HomeWidgetService _instance = HomeWidgetService._internal();
  factory HomeWidgetService() => _instance;
  HomeWidgetService._internal();

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

  /// Pulls the latest live state from Firestore & caches, pushing updates to all widgets
  Future<void> syncAllWidgets() async {
    if (kIsWeb) return;

    try {
      // 1. Sync Gold Widget
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

      // 2. Sync Finance Widget
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final accountsSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('finance_accounts')
          .get();

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

      // Compute Inflow and Outflow for Today
      double todayIn = 0.0;
      double todayOut = 0.0;

      final manualTxSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('finance_transactions')
          .get();

      for (final doc in manualTxSnap.docs) {
        final data = doc.data();
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

      final smsTxSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('sms_transactions')
          .get();

      for (final doc in smsTxSnap.docs) {
        final data = doc.data();
        DateTime? dt;
        final ts = data['timestamp'] ?? data['date'];
        if (ts is Timestamp) {
          dt = ts.toDate();
        } else if (ts is String) {
          dt = DateTime.tryParse(ts);
        } else if (ts is int) {
          dt = DateTime.fromMillisecondsSinceEpoch(ts);
        }

        final cat = (data['category'] ?? '').toString();
        if (cat.contains('Ignored') || cat == 'Self Transfer') continue;

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

      // 3. Sync Shift Widget
      final currentRosterMonth = DateFormat('yyyy-MM').format(now);
      final todayShiftDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('shifts')
          .doc(currentRosterMonth)
          .collection('daily_shifts')
          .doc(todayStr)
          .get();

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
          .get();

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

      await updateShiftWidget(
        todayShiftName: todayName,
        todayShiftTime: todayTime,
        tomorrowShiftName: tomorrowName,
      );
    } catch (e) {
      LogService().error('Error in syncAllWidgets', e);
    }
  }
}
