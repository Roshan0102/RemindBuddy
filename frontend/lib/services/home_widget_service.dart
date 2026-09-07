import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import '../models/shift.dart';
import 'log_service.dart';

class HomeWidgetService {
  static final HomeWidgetService _instance = HomeWidgetService._internal();
  factory HomeWidgetService() => _instance;
  HomeWidgetService._internal();

  StreamSubscription? _accountsSub;
  StreamSubscription? _smsTxSub;
  StreamSubscription? _manualTxSub;

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

    // 3. Sync Shift Widget
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final now = DateTime.now();
        final todayStr = DateFormat('yyyy-MM-dd').format(now);
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

        // Also dynamically sync the full Shift Calendar Widget
        try {
          final monthShiftsSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('shifts')
              .doc(currentRosterMonth)
              .collection('daily_shifts')
              .get();

          if (monthShiftsSnapshot.docs.isNotEmpty) {
            final List<Shift> monthShifts = monthShiftsSnapshot.docs.map((d) {
              final sData = d.data();
              return Shift.fromJson(sData);
            }).toList();

            await updateShiftCalendarWidget(
              shifts: monthShifts,
              monthDate: now,
            );
          }
        } catch (calErr) {
          LogService().error('Error syncing Shift Calendar Widget in syncAllWidgets', calErr);
        }
      }
    } catch (e) {
      LogService().error('Error syncing Shift Widget in syncAllWidgets', e);
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
      final widget = _buildShiftCalendarWidgetView(shifts: shifts, monthDate: monthDate);

      final imageUri = await HomeWidget.renderFlutterWidget(
        widget,
        key: 'shift_calendar_image',
        logicalSize: const Size(360, 360),
        pixelRatio: 2.5,
      );

      if (imageUri != null) {
        await HomeWidget.saveWidgetData<String>('shift_calendar_image_path', imageUri.path);
      }
      await HomeWidget.saveWidgetData<String>('shift_calendar_month', monthTitle);

      await HomeWidget.updateWidget(
        name: 'ShiftCalendarWidgetProvider',
        androidName: 'ShiftCalendarWidgetProvider',
        qualifiedAndroidName: 'com.remindbuddy.remindbuddy.ShiftCalendarWidgetProvider',
      );
    } catch (e) {
      LogService().error('Failed to update ShiftCalendarWidget', e);
    }
  }

  Widget _buildShiftCalendarWidgetView({
    required List<Shift> shifts,
    required DateTime monthDate,
  }) {
    final year = monthDate.year;
    final month = monthDate.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday % 7;
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final Map<String, Shift> shiftByDate = {
      for (var s in shifts) s.date: s,
    };

    final weekHeaders = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

    return Container(
      width: 360,
      height: 360,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F141C),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('MMMM yyyy').format(monthDate).toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  decoration: TextDecoration.none,
                ),
              ),
              const Text(
                'RemindBuddy Shifts',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 10,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Weekday headers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekHeaders.map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),

          // Grid
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: firstWeekday + daysInMonth,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
                childAspectRatio: 0.88,
              ),
              itemBuilder: (context, index) {
                if (index < firstWeekday) {
                  return const SizedBox.shrink();
                }

                final day = index - firstWeekday + 1;
                final dateStr = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                final isToday = dateStr == todayStr;
                final shift = shiftByDate[dateStr];

                Color badgeColor = Colors.transparent;
                String badgeText = '';

                if (shift != null) {
                  switch (shift.shiftType.toLowerCase()) {
                    case 'morning':
                      badgeColor = const Color(0xFFF59E0B);
                      badgeText = 'M';
                      break;
                    case 'afternoon':
                      badgeColor = const Color(0xFF06B6D4);
                      badgeText = 'A';
                      break;
                    case 'night':
                      badgeColor = const Color(0xFF8B5CF6);
                      badgeText = 'N';
                      break;
                    case 'week_off':
                      badgeColor = const Color(0xFF10B981);
                      badgeText = 'OFF';
                      break;
                  }
                }

                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2638),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isToday ? const Color(0xFF38BDF8) : const Color(0xFF263248),
                      width: isToday ? 1.5 : 0.8,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                          color: isToday ? const Color(0xFF38BDF8) : const Color(0xFFE2E8F0),
                          decoration: TextDecoration.none,
                        ),
                      ),
                      if (shift != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            badgeText,
                            style: const TextStyle(
                              fontSize: 7.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              decoration: TextDecoration.none,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        const SizedBox(height: 8),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),

          // Mini Legend Row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildWidgetLegendDot('Morning (M)', const Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              _buildWidgetLegendDot('Afternoon (A)', const Color(0xFF06B6D4)),
              const SizedBox(width: 8),
              _buildWidgetLegendDot('Night (N)', const Color(0xFF8B5CF6)),
              const SizedBox(width: 8),
              _buildWidgetLegendDot('Off Day', const Color(0xFF10B981)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWidgetLegendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 8,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}
