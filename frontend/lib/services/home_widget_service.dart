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

  /// Updates the Gold Rates Home Screen Widget
  Future<void> updateGoldWidget({
    required double rate24k,
    required double rate22k,
    required double changeToday,
    required String city,
  }) async {
    if (kIsWeb) return;
    try {
      final String changeText = changeToday >= 0
          ? '▲ +₹${changeToday.abs().toStringAsFixed(0)} Today'
          : '▼ -₹${changeToday.abs().toStringAsFixed(0)} Today';

      final String timeText = 'Updated ${DateFormat('hh:mm a').format(DateTime.now())}';

      await HomeWidget.saveWidgetData<String>('gold_24k', '₹${rate24k.toStringAsFixed(0)}/g');
      await HomeWidget.saveWidgetData<String>('gold_22k', '₹${rate22k.toStringAsFixed(0)}/g');
      await HomeWidget.saveWidgetData<String>('gold_city', city.isNotEmpty ? city : 'Chennai');
      await HomeWidget.saveWidgetData<String>('gold_change', changeText);
      await HomeWidget.saveWidgetData<String>('gold_time', timeText);

      await HomeWidget.updateWidget(androidName: 'GoldWidgetProvider');
    } catch (e) {
      LogService().error('Failed to update GoldWidget', e);
    }
  }

  /// Updates the Bank Balance & Cashflow Home Screen Widget
  Future<void> updateFinanceWidget({
    required double totalBalance,
    required double todayIn,
    required double todayOut,
    required String bankName,
  }) async {
    if (kIsWeb) return;
    try {
      final currencyFormat = NumberFormat('#,##,##0');
      final String balanceText = '₹${currencyFormat.format(totalBalance)}';
      final String inText = '↓ +₹${currencyFormat.format(todayIn)} In';
      final String outText = '↑ -₹${currencyFormat.format(todayOut)} Out';
      final String timeText = 'Synced ${DateFormat('hh:mm a').format(DateTime.now())}';

      await HomeWidget.saveWidgetData<String>('finance_balance', balanceText);
      await HomeWidget.saveWidgetData<String>('finance_in', inText);
      await HomeWidget.saveWidgetData<String>('finance_out', outText);
      await HomeWidget.saveWidgetData<String>('finance_bank', bankName.isNotEmpty ? bankName : 'Active Accounts');
      await HomeWidget.saveWidgetData<String>('finance_time', timeText);

      await HomeWidget.updateWidget(androidName: 'FinanceWidgetProvider');
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
      final String tomorrowText = 'Tomorrow: $tomorrowShiftName';

      await HomeWidget.saveWidgetData<String>('shift_name', todayShiftName);
      await HomeWidget.saveWidgetData<String>('shift_time', todayShiftTime);
      await HomeWidget.saveWidgetData<String>('shift_tomorrow', tomorrowText);
      await HomeWidget.saveWidgetData<String>('shift_date', dateText);

      await HomeWidget.updateWidget(androidName: 'ShiftWidgetProvider');
    } catch (e) {
      LogService().error('Failed to update ShiftWidget', e);
    }
  }

  /// Pulls the latest live state from Firestore & caches, pushing updates to all widgets
  Future<void> syncAllWidgets() async {
    if (kIsWeb) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 1. Sync Gold Widget
      final goldSnap = await FirebaseFirestore.instance
          .collection('gold_prices')
          .orderBy('timestamp', descending: true)
          .limit(2)
          .get();

      if (goldSnap.docs.isNotEmpty) {
        final latest = goldSnap.docs.first.data();
        final double rate24k = (latest['rate24k'] as num?)?.toDouble() ?? 7850.0;
        final double rate22k = (latest['rate22k'] as num?)?.toDouble() ?? 7200.0;
        final String city = latest['city']?.toString() ?? 'Chennai';

        double change = 0.0;
        if (goldSnap.docs.length > 1) {
          final prev = goldSnap.docs[1].data();
          final double prev24k = (prev['rate24k'] as num?)?.toDouble() ?? rate24k;
          change = rate24k - prev24k;
        }

        await updateGoldWidget(
          rate24k: rate24k,
          rate22k: rate22k,
          changeToday: change,
          city: city,
        );
      }

      // 2. Sync Finance Widget
      final accountsSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('bank_accounts')
          .get();

      double totalBalance = 0.0;
      for (var d in accountsSnap.docs) {
        final bal = (d.data()['balance'] as num?)?.toDouble() ?? 0.0;
        totalBalance += bal;
      }

      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final todayTxs = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('sms_transactions')
          .where('timestamp', isGreaterThanOrEqualTo: startOfDay.toIso8601String())
          .get();

      double todayIn = 0.0;
      double todayOut = 0.0;
      for (var d in todayTxs.docs) {
        final data = d.data();
        final amt = (data['amount'] as num?)?.toDouble() ?? 0.0;
        final type = data['type']?.toString() ?? 'Debit';
        if (type == 'Credit') {
          todayIn += amt;
        } else {
          todayOut += amt;
        }
      }

      await updateFinanceWidget(
        totalBalance: totalBalance,
        todayIn: todayIn,
        todayOut: todayOut,
        bankName: accountsSnap.docs.length == 1
            ? (accountsSnap.docs.first.data()['bankName'] ?? 'Active Bank')
            : '${accountsSnap.docs.length} Active Accounts',
      );

      // 3. Sync Shift Widget
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final tomorrowStr = DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)));

      final shiftDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('shifts')
          .doc('metadata')
          .get();

      if (shiftDoc.exists) {
        final data = shiftDoc.data() ?? {};
        final activeRosterId = data['activeRosterId']?.toString();

        if (activeRosterId != null && activeRosterId.isNotEmpty) {
          final rosterDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('monthly_rosters')
              .doc(activeRosterId)
              .get();

          if (rosterDoc.exists) {
            final shiftsList = (rosterDoc.data()?['shifts'] as List<dynamic>?) ?? [];
            String todayName = 'No Shift';
            String todayTime = 'Off Duty';
            String tomorrowName = 'No Shift';

            for (var item in shiftsList) {
              if (item is Map) {
                final date = item['date']?.toString() ?? '';
                final title = item['title']?.toString() ?? item['type']?.toString() ?? 'Shift';
                final start = item['startTime']?.toString() ?? '';
                final end = item['endTime']?.toString() ?? '';

                if (date == todayStr) {
                  todayName = title;
                  todayTime = (start.isNotEmpty && end.isNotEmpty) ? '$start - $end' : 'Scheduled Shift';
                } else if (date == tomorrowStr) {
                  tomorrowName = (start.isNotEmpty) ? '$title ($start)' : title;
                }
              }
            }

            await updateShiftWidget(
              todayShiftName: todayName,
              todayShiftTime: todayTime,
              tomorrowShiftName: tomorrowName,
            );
          }
        }
      }
    } catch (e) {
      LogService().error('Error in syncAllWidgets', e);
    }
  }
}
