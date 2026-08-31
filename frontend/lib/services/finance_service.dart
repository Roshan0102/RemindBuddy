import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/bank_account.dart';
import '../models/finance_transaction.dart';
import '../models/recurring_bill.dart';
import '../models/debt_record.dart';
import '../models/group_split.dart';
import '../models/sms_transaction.dart';
import 'sms_parser_service.dart';
import 'payment_notification_tracker_service.dart';
import 'home_widget_service.dart';

class FinanceService {
  static final FinanceService _instance = FinanceService._internal();
  factory FinanceService() => _instance;
  FinanceService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const EventChannel _smsStreamChannel = EventChannel('com.remindbuddy/sms_stream');
  dynamic _smsEventSubscription;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference? get _userDoc {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid);
  }

  void initGlobalSmsListener() {
    try {
      _smsEventSubscription?.cancel();
      _smsEventSubscription = _smsStreamChannel.receiveBroadcastStream().listen((dynamic event) {
        if (event is Map) {
          final sender = event['sender']?.toString() ?? '';
          final body = event['body']?.toString() ?? '';
          final timestamp = (event['timestamp'] is num) ? (event['timestamp'] as num).toInt() : DateTime.now().millisecondsSinceEpoch;

          final parsed = SmsParserService.parseSms(sender, body, timestamp);
          if (parsed != null) {
            saveSmsTransaction(parsed);
          }
        }
      }, onError: (err) {
        debugPrint('Global SMS EventChannel stream error: $err');
      });

      // Also drain any pending background SMS from buffer
      checkAndProcessPendingBackgroundSms();

      // Initialize live UPI app notification listener & buffer drain
      PaymentNotificationTrackerService().init();
    } catch (e) {
      debugPrint('Error initializing global SMS & Notification listeners: $e');
    }
  }

  // ============================================================================
  // BANK ACCOUNTS
  // ============================================================================

  Stream<List<BankAccount>> getAccountsStream() {
    final doc = _userDoc;
    if (doc == null) return Stream.value([]);

    return doc
        .collection('finance_accounts')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => BankAccount.fromMap(d.data(), d.id)).toList());
  }

  Future<void> addAccount(BankAccount account) async {
    final doc = _userDoc;
    if (doc == null) return;

    final ref = doc.collection('finance_accounts').doc();
    final newAccount = BankAccount(
      id: ref.id,
      name: account.name,
      accountType: account.accountType,
      initialBalance: account.initialBalance,
      currentBalance: account.initialBalance, // Start with initial balance
      colorHex: account.colorHex,
      iconName: account.iconName,
      updatedAt: DateTime.now(),
    );
    await ref.set(newAccount.toMap());
    HomeWidgetService().syncAllWidgets();
  }

  Future<void> updateAccount(BankAccount account) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.collection('finance_accounts').doc(account.id).update(account.toMap());
    HomeWidgetService().syncAllWidgets();
  }

  Future<void> deleteAccount(String accountId) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.collection('finance_accounts').doc(accountId).delete();
    HomeWidgetService().syncAllWidgets();
  }

  // ============================================================================
  // TRANSACTIONS
  // ============================================================================

  Stream<List<FinanceTransaction>> getTransactionsStream({String? accountId}) {
    final doc = _userDoc;
    if (doc == null) return Stream.value([]);

    Query query = doc.collection('finance_transactions').orderBy('timestamp', descending: true);
    if (accountId != null && accountId.isNotEmpty) {
      query = query.where('accountId', isEqualTo: accountId);
    }

    return query.snapshots().map(
        (snap) => snap.docs.map((d) => FinanceTransaction.fromMap(d.data() as Map<String, dynamic>, d.id)).toList());
  }

  Future<void> addTransaction(FinanceTransaction tx) async {
    final doc = _userDoc;
    if (doc == null) return;

    final batch = _db.batch();
    final txRef = doc.collection('finance_transactions').doc();
    
    batch.set(txRef, tx.toMap());

    // Update account balance
    final accountRef = doc.collection('finance_accounts').doc(tx.accountId);
    final accountSnap = await accountRef.get();
    if (accountSnap.exists) {
      final account = BankAccount.fromMap(accountSnap.data() as Map<String, dynamic>, accountSnap.id);
      final double delta = tx.type == 'income' ? tx.amount : -tx.amount;
      final double newBal = account.currentBalance + delta;

      batch.update(accountRef, {
        'currentBalance': newBal,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    }

    await batch.commit();
    HomeWidgetService().syncAllWidgets();
  }

  Future<void> deleteTransaction(FinanceTransaction tx) async {
    final doc = _userDoc;
    if (doc == null) return;

    final batch = _db.batch();
    batch.delete(doc.collection('finance_transactions').doc(tx.id));

    // Reverse balance change
    final accountRef = doc.collection('finance_accounts').doc(tx.accountId);
    final accountSnap = await accountRef.get();
    if (accountSnap.exists) {
      final account = BankAccount.fromMap(accountSnap.data() as Map<String, dynamic>, accountSnap.id);
      final double delta = tx.type == 'income' ? -tx.amount : tx.amount;
      final double newBal = account.currentBalance + delta;

      batch.update(accountRef, {
        'currentBalance': newBal,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    }

    await batch.commit();
    HomeWidgetService().syncAllWidgets();
  }

  // ============================================================================
  // RECURRING BILLS & SUBSCRIPTIONS
  // ============================================================================

  Stream<List<RecurringBill>> getBillsStream() {
    final doc = _userDoc;
    if (doc == null) return Stream.value([]);

    return doc
        .collection('finance_bills')
        .orderBy('dueDate', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) => RecurringBill.fromMap(d.data(), d.id)).toList());
  }

  Future<void> addBill(RecurringBill bill) async {
    final doc = _userDoc;
    if (doc == null) return;

    final ref = doc.collection('finance_bills').doc();
    final newBill = RecurringBill(
      id: ref.id,
      title: bill.title,
      amount: bill.amount,
      category: bill.category,
      dueDate: bill.dueDate,
      frequency: bill.frequency,
      accountId: bill.accountId,
      isActive: bill.isActive,
      notes: bill.notes,
    );
    await ref.set(newBill.toMap());
    HomeWidgetService().syncAllWidgets();
  }

  Future<void> updateBill(RecurringBill bill) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.collection('finance_bills').doc(bill.id).update(bill.toMap());
    HomeWidgetService().syncAllWidgets();
  }

  Future<void> deleteBill(String billId) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.collection('finance_bills').doc(billId).delete();
    HomeWidgetService().syncAllWidgets();
  }

  // ============================================================================
  // LENT & BORROWED DEBTS
  // ============================================================================

  Stream<List<DebtRecord>> getDebtsStream() {
    final doc = _userDoc;
    if (doc == null) return Stream.value([]);

    return doc
        .collection('finance_debts')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => DebtRecord.fromMap(d.data(), d.id)).toList());
  }

  Future<void> addDebt(DebtRecord debt, {bool updateAccountBalance = true}) async {
    final doc = _userDoc;
    if (doc == null) return;

    final batch = _db.batch();
    final debtRef = doc.collection('finance_debts').doc();
    batch.set(debtRef, debt.toMap());

    // If linked to an account and updateAccountBalance is true:
    // 'lent' = money left account (-amount, logged as expense/lent)
    // 'borrowed' = money came into account (+amount, logged as income/borrowed)
    if (updateAccountBalance && debt.accountId != null && debt.accountId!.isNotEmpty) {
      final accountRef = doc.collection('finance_accounts').doc(debt.accountId);
      final accountSnap = await accountRef.get();
      if (accountSnap.exists) {
        final account = BankAccount.fromMap(accountSnap.data() as Map<String, dynamic>, accountSnap.id);
        final double delta = debt.type == 'lent' ? -debt.amount : debt.amount;
        final double newBal = account.currentBalance + delta;
        batch.update(accountRef, {
          'currentBalance': newBal,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });

        // Also add a transaction record
        final txRef = doc.collection('finance_transactions').doc();
        final tx = FinanceTransaction(
          id: txRef.id,
          accountId: debt.accountId!,
          type: debt.type == 'lent' ? 'expense' : 'income',
          amount: debt.amount,
          category: 'Debt / Loan',
          note: debt.type == 'lent'
              ? 'Lent to ${debt.personName}: ${debt.note}'
              : 'Borrowed from ${debt.personName}: ${debt.note}',
          timestamp: debt.date,
        );
        batch.set(txRef, tx.toMap());
      }
    }

    await batch.commit();
    HomeWidgetService().syncAllWidgets();
  }

  Future<void> settleDebt(DebtRecord debt, String targetAccountId) async {
    final doc = _userDoc;
    if (doc == null) return;

    final batch = _db.batch();
    final debtRef = doc.collection('finance_debts').doc(debt.id);
    batch.update(debtRef, {'isSettled': true});

    // If settling:
    // 'lent' (they owed me, now paid back) = money comes INTO target account (+amount)
    // 'borrowed' (I owed them, now I paid) = money leaves target account (-amount)
    if (targetAccountId.isNotEmpty) {
      final accountRef = doc.collection('finance_accounts').doc(targetAccountId);
      final accountSnap = await accountRef.get();
      if (accountSnap.exists) {
        final account = BankAccount.fromMap(accountSnap.data() as Map<String, dynamic>, accountSnap.id);
        final double delta = debt.type == 'lent' ? debt.amount : -debt.amount;
        final double newBal = account.currentBalance + delta;
        batch.update(accountRef, {
          'currentBalance': newBal,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });

        // Log transaction for settlement
        final txRef = doc.collection('finance_transactions').doc();
        final tx = FinanceTransaction(
          id: txRef.id,
          accountId: targetAccountId,
          type: debt.type == 'lent' ? 'income' : 'expense',
          amount: debt.amount,
          category: 'Debt Settlement',
          note: debt.type == 'lent'
              ? 'Settled: ${debt.personName} paid back'
              : 'Settled: Paid back to ${debt.personName}',
          timestamp: DateTime.now(),
        );
        batch.set(txRef, tx.toMap());
      }
    }

    await batch.commit();
    HomeWidgetService().syncAllWidgets();
  }

  Future<void> settleDebtById(String debtId) async {
    final doc = _userDoc;
    if (doc == null) return;
    await doc.collection('finance_debts').doc(debtId).update({'isSettled': true});
    HomeWidgetService().syncAllWidgets();
  }

  Future<void> deleteDebt(String debtId) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.collection('finance_debts').doc(debtId).delete();
    HomeWidgetService().syncAllWidgets();
  }

  // ============================================================================
  // GROUP BILL SPLITTING
  // ============================================================================

  Stream<List<GroupEvent>> getGroupEventsStream() {
    final doc = _userDoc;
    if (doc == null) return Stream.value([]);

    return doc
        .collection('finance_group_events')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => GroupEvent.fromMap(d.data(), d.id)).toList());
  }

  Future<void> addGroupEvent(GroupEvent event) async {
    final doc = _userDoc;
    if (doc == null) return;

    final ref = doc.collection('finance_group_events').doc();
    final newEvent = GroupEvent(
      id: ref.id,
      title: event.title,
      members: event.members,
      createdAt: DateTime.now(),
    );
    await ref.set(newEvent.toMap());
  }

  Future<void> deleteGroupEvent(String eventId) async {
    final doc = _userDoc;
    if (doc == null) return;

    final batch = _db.batch();
    batch.delete(doc.collection('finance_group_events').doc(eventId));

    // Also delete all expenses in this group
    final expSnap = await doc.collection('finance_group_expenses').where('groupId', isEqualTo: eventId).get();
    for (final expDoc in expSnap.docs) {
      batch.delete(expDoc.reference);
    }

    await batch.commit();
  }

  Stream<List<GroupExpense>> getGroupExpensesStream(String groupId) {
    final doc = _userDoc;
    if (doc == null) return Stream.value([]);

    return doc
        .collection('finance_group_expenses')
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) => GroupExpense.fromMap(d.data(), d.id)).toList();
          list.sort((a, b) => b.date.compareTo(a.date));
          return list;
        });
  }

  Future<void> addGroupExpense(GroupExpense expense) async {
    final doc = _userDoc;
    if (doc == null) return;

    final ref = doc.collection('finance_group_expenses').doc();
    final newExp = GroupExpense(
      id: ref.id,
      groupId: expense.groupId,
      description: expense.description,
      amount: expense.amount,
      payerName: expense.payerName,
      involvedMembers: expense.involvedMembers,
      date: expense.date,
    );
    await ref.set(newExp.toMap());
  }

  Future<void> deleteGroupExpense(String expenseId) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.collection('finance_group_expenses').doc(expenseId).delete();
  }

  /// Calculates net balances for members in a group and computes optimal settlements.
  List<GroupSettlement> calculateGroupBalances(List<String> members, List<GroupExpense> expenses) {
    final Map<String, double> netMap = {};
    for (final m in members) {
      netMap[m] = 0.0;
    }

    for (final exp in expenses) {
      if (exp.involvedMembers.isEmpty || exp.amount <= 0) continue;

      final double splitAmount = exp.amount / exp.involvedMembers.length;
      
      // Each involved member owes splitAmount
      for (final member in exp.involvedMembers) {
        netMap[member] = (netMap[member] ?? 0.0) - splitAmount;
      }

      // Payer is credited the full amount
      netMap[exp.payerName] = (netMap[exp.payerName] ?? 0.0) + exp.amount;
    }

    // Separate debtors (< 0) and creditors (> 0)
    final List<MapEntry<String, double>> debtors = [];
    final List<MapEntry<String, double>> creditors = [];

    netMap.forEach((person, net) {
      if (net < -0.01) {
        debtors.add(MapEntry(person, -net)); // store as positive debt amount
      } else if (net > 0.01) {
        creditors.add(MapEntry(person, net));
      }
    });

    final List<GroupSettlement> settlements = [];

    int dIdx = 0;
    int cIdx = 0;

    while (dIdx < debtors.length && cIdx < creditors.length) {
      final debtor = debtors[dIdx];
      final creditor = creditors[cIdx];

      final double settleAmt = debtor.value < creditor.value ? debtor.value : creditor.value;

      settlements.add(GroupSettlement(
        fromPerson: debtor.key,
        toPerson: creditor.key,
        amount: settleAmt,
      ));

      debtors[dIdx] = MapEntry(debtor.key, debtor.value - settleAmt);
      creditors[cIdx] = MapEntry(creditor.key, creditor.value - settleAmt);

      if (debtors[dIdx].value < 0.01) dIdx++;
      if (creditors[cIdx].value < 0.01) cIdx++;
    }

    return settlements;
  }

  // ============================================================================
  // AUTOMATED SMS TRANSACTIONS
  // ============================================================================

  Stream<List<SmsTransaction>> getSmsTransactionsStream() {
    final doc = _userDoc;
    if (doc == null) return Stream.value([]);

    return doc
        .collection('sms_transactions')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => SmsTransaction.fromMap(d.data())).toList());
  }

  Future<void> saveSmsTransaction(SmsTransaction tx) async {
    final doc = _userDoc;
    if (doc == null) return;

    // Route through 5-Stage Smart Deduplication Engine
    await PaymentNotificationTrackerService().processAndReconcileTransaction(tx);
    HomeWidgetService().syncAllWidgets();
  }

  Future<void> updateSmsTransaction(SmsTransaction tx, {String? destinationBankAccountId}) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.collection('sms_transactions').doc(tx.id).update(tx.toMap());

    // If verified, reconcile transaction balance to corresponding BankAccount if matching
    if (tx.isVerified) {
      await _reconcileSmsTransactionWithAccount(tx, destinationBankAccountId: destinationBankAccountId);
    }
    HomeWidgetService().syncAllWidgets();
  }

  Future<void> deleteSmsTransaction(String id) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.collection('sms_transactions').doc(id).delete();
    HomeWidgetService().syncAllWidgets();
  }

  /// Deletes all SMS transaction records for a specific month & year
  Future<int> deleteSmsTransactionsForMonth(DateTime monthYear) async {
    final doc = _userDoc;
    if (doc == null) return 0;

    final snap = await doc.collection('sms_transactions').get();
    final batch = _db.batch();
    int count = 0;

    for (final d in snap.docs) {
      final data = d.data();
      final dynamic rawTs = data['timestamp'];
      DateTime? date;
      if (rawTs is Timestamp) {
        date = rawTs.toDate();
      } else if (rawTs is int) {
        date = DateTime.fromMillisecondsSinceEpoch(rawTs);
      } else if (rawTs is String) {
        date = DateTime.tryParse(rawTs);
      }

      if (date != null && date.year == monthYear.year && date.month == monthYear.month) {
        batch.delete(d.reference);
        count++;
      }
    }

    if (count > 0) {
      await batch.commit();
      HomeWidgetService().syncAllWidgets();
    }
    return count;
  }

  Future<void> _reconcileSmsTransactionWithAccount(SmsTransaction tx, {String? destinationBankAccountId}) async {
    final doc = _userDoc;
    if (doc == null) return;

    // Exclude Ignored / Not Needed transactions from balance changes
    if (tx.category == 'Ignored / Not Needed' || tx.category == 'Ignored') {
      return;
    }

    final accountsSnap = await doc.collection('finance_accounts').get();
    if (accountsSnap.docs.isEmpty) return;

    final accounts = accountsSnap.docs.map((d) => BankAccount.fromMap(d.data(), d.id)).toList();

    // Handle Self Transfer: Deduct from source bank, Add to destination bank
    if (tx.category == 'Self Transfer' && destinationBankAccountId != null && destinationBankAccountId.isNotEmpty) {
      BankAccount? sourceBank = accounts.firstWhere(
        (a) => a.name.toLowerCase().contains(tx.bankName.toLowerCase()) || tx.bankName.toLowerCase().contains(a.name.toLowerCase()),
        orElse: () => accounts.first,
      );
      BankAccount? destBank = accounts.firstWhere(
        (a) => a.id == destinationBankAccountId,
        orElse: () => accounts.last,
      );

      if (sourceBank.id != destBank.id) {
        // Deduct from Source
        await doc.collection('finance_accounts').doc(sourceBank.id).update({
          'currentBalance': sourceBank.currentBalance - tx.amount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        // Add to Destination
        await doc.collection('finance_accounts').doc(destBank.id).update({
          'currentBalance': destBank.currentBalance + tx.amount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        HomeWidgetService().syncAllWidgets();
      }
      return;
    }

    // Normal Debit or Credit Sync to Bank Account
    for (final accountDoc in accountsSnap.docs) {
      final bank = BankAccount.fromMap(accountDoc.data(), accountDoc.id);

      final bool nameMatch = bank.name.toLowerCase().contains(tx.bankName.toLowerCase()) ||
          tx.bankName.toLowerCase().contains(bank.name.toLowerCase());
      final bool last4Match = tx.accountLast4.isNotEmpty && bank.name.contains(tx.accountLast4);

      if (nameMatch || last4Match) {
        final double change = (tx.type == 'Debit') ? -tx.amount : tx.amount;
        final double newBal = bank.currentBalance + change;
        await accountDoc.reference.update({
          'currentBalance': newBal,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        HomeWidgetService().syncAllWidgets();
        break; // Matched and updated
      }
    }
  }

  /// Scans past SMS messages from Android Content Provider and saves newly detected transactions
  Future<int> scanPastSmsInbox({int days = 30, DateTime? startCutoff, DateTime? endCutoff}) async {
    int count = 0;
    try {
      final List<dynamic>? rawList = await const MethodChannel('com.remindbuddy/sms_scanner')
          .invokeListMethod('scanSmsInbox', {'days': days});

      if (rawList != null) {
        for (final item in rawList) {
          if (item is Map) {
            final String sender = item['sender']?.toString() ?? '';
            final String body = item['body']?.toString() ?? '';
            final int timestamp = (item['timestamp'] is num) ? (item['timestamp'] as num).toInt() : 0;

            final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
            if (startCutoff != null && dt.isBefore(startCutoff)) continue;
            if (endCutoff != null && dt.isAfter(endCutoff)) continue;

            final parsed = SmsParserService.parseSms(sender, body, timestamp);
            if (parsed != null) {
              await saveSmsTransaction(parsed);
              count++;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning SMS inbox: $e');
    }
    return count;
  }

  /// Checks for any SMS messages captured while the app was closed/terminated in background
  Future<int> checkAndProcessPendingBackgroundSms() async {
    int count = 0;
    try {
      final List<dynamic>? rawList = await const MethodChannel('com.remindbuddy/sms_buffer')
          .invokeListMethod('getAndClearPendingSms');

      if (rawList != null && rawList.isNotEmpty) {
        for (final item in rawList) {
          if (item is Map) {
            final String sender = item['sender']?.toString() ?? '';
            final String body = item['body']?.toString() ?? '';
            final int timestamp = (item['timestamp'] is num) ? (item['timestamp'] as num).toInt() : 0;

            final parsed = SmsParserService.parseSms(sender, body, timestamp);
            if (parsed != null) {
              await saveSmsTransaction(parsed);
              count++;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking background SMS buffer: $e');
    }
    return count;
  }

  /// Scans past 15 days of SMS messages and uploads raw SMS samples to 'sms_study_samples' collection in Firestore for AI research
  Future<int> uploadSmsStudySamples({int days = 15}) async {
    int count = 0;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('uploadSmsStudySamples: User is null');
        return 0;
      }

      final List<dynamic>? rawList = await const MethodChannel('com.remindbuddy/sms_scanner')
          .invokeListMethod('scanSmsInbox', {'days': days});

      if (rawList != null && rawList.isNotEmpty) {
        final globalRef = _db.collection('sms_study_samples');
        final userSubRef = _db.collection('users').doc(user.uid).collection('sms_study_samples');

        var batch = _db.batch();
        int batchCount = 0;

        for (final item in rawList) {
          if (item is Map) {
            final String sender = item['sender']?.toString() ?? '';
            final String body = item['body']?.toString() ?? '';
            final int timestamp = (item['timestamp'] is num) ? (item['timestamp'] as num).toInt() : 0;

            if (body.isNotEmpty) {
              final String sampleId = globalRef.doc().id;
              final data = {
                'sampleId': sampleId,
                'userId': user.uid,
                'userEmail': user.email ?? 'Unknown Email',
                'userName': user.displayName ?? 'RemindBuddy User',
                'sender': sender,
                'body': body,
                'timestamp': timestamp,
                'syncedAt': FieldValue.serverTimestamp(),
              };

              batch.set(globalRef.doc(sampleId), data);
              batch.set(userSubRef.doc(sampleId), data);

              count++;
              batchCount += 2;

              if (batchCount >= 400) {
                await batch.commit();
                batch = _db.batch();
                batchCount = 0;
              }
            }
          }
        }

        if (batchCount > 0) {
          await batch.commit();
        }
      }
    } catch (e) {
      debugPrint('Error uploading SMS study samples: $e');
    }
    return count;
  }

  // ============================================================================
  // USER CUSTOM TAGS (PERSISTENCE & SYNC)
  // ============================================================================

  Stream<List<String>> getUserCustomTagsStream() {
    final doc = _userDoc;
    if (doc == null) return Stream.value([]);

    return doc.snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return [];
      final data = snap.data() as Map<String, dynamic>;
      final List<dynamic> tags = data['customTags'] ?? [];
      return tags.map((e) => e.toString()).toList();
    });
  }

  Future<void> saveUserCustomTag(String tag) async {
    final cleanTag = tag.trim();
    if (cleanTag.isEmpty) return;

    final doc = _userDoc;
    if (doc == null) return;

    final snap = await doc.get();
    List<String> existingTags = [];
    if (snap.exists && snap.data() != null) {
      final data = snap.data() as Map<String, dynamic>;
      final List<dynamic> list = data['customTags'] ?? [];
      existingTags = list.map((e) => e.toString()).toList();
    }

    // Remove duplicates case-insensitively and prepend to top (most recent)
    existingTags.removeWhere((t) => t.toLowerCase() == cleanTag.toLowerCase());
    existingTags.insert(0, cleanTag);

    // Keep max 50 recent tags stored in Firestore
    if (existingTags.length > 50) {
      existingTags = existingTags.sublist(0, 50);
    }

    await doc.set({'customTags': existingTags}, SetOptions(merge: true));
  }

  // ============================================================================
  // USER CUSTOM CATEGORIES (PERSISTENCE & SYNC)
  // ============================================================================

  Stream<List<String>> getUserCustomCategoriesStream() {
    final doc = _userDoc;
    if (doc == null) return Stream.value([]);

    return doc.snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return [];
      final data = snap.data() as Map<String, dynamic>;
      final List<dynamic> list = data['customCategories'] ?? [];
      return list.map((e) => e.toString()).toList();
    });
  }

  Future<void> saveUserCustomCategory(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;

    final doc = _userDoc;
    if (doc == null) return;

    final snap = await doc.get();
    List<String> existing = [];
    if (snap.exists && snap.data() != null) {
      final data = snap.data() as Map<String, dynamic>;
      final List<dynamic> list = data['customCategories'] ?? [];
      existing = list.map((e) => e.toString()).toList();
    }

    if (!existing.any((c) => c.toLowerCase() == cleanName.toLowerCase())) {
      existing.add(cleanName);
      await doc.set({'customCategories': existing}, SetOptions(merge: true));
    }
  }

  // ============================================================================
  // USER SMS HEADER -> BANK RULES (CUSTOM KEYWORD RULES)
  // ============================================================================

  Stream<List<Map<String, String>>> getCustomHeaderBankRulesStream() {
    final doc = _userDoc;
    if (doc == null) return Stream.value([]);

    return doc.snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return [];
      final data = snap.data() as Map<String, dynamic>;
      
      if (data.containsKey('customHeaderBankRules') && data['customHeaderBankRules'] is List) {
        final List<dynamic> list = data['customHeaderBankRules'];
        final List<Map<String, String>> result = [];
        for (final item in list) {
          if (item is Map) {
            final p = (item['pattern'] ?? '').toString().trim().toUpperCase();
            final b = (item['bankName'] ?? '').toString().trim();
            if (p.isNotEmpty && b.isNotEmpty) {
              result.add({'pattern': p, 'bankName': b});
            }
          }
        }
        return result;
      }

      // Legacy fallback: convert old headerBankMappings Map to List<Map<String, String>> rules
      final Map<String, dynamic> rawMap = data['headerBankMappings'] ?? {};
      final List<Map<String, String>> result = [];
      rawMap.forEach((key, value) {
        final p = key.toString().trim().toUpperCase();
        final b = value.toString().trim();
        if (p.isNotEmpty && b.isNotEmpty) {
          result.add({'pattern': p, 'bankName': b});
        }
      });
      return result;
    });
  }

  Future<void> saveCustomHeaderBankRules(List<Map<String, String>> rules) async {
    final doc = _userDoc;
    if (doc == null) return;

    final cleanedRules = rules.map((r) => {
      'pattern': r['pattern']!.trim().toUpperCase(),
      'bankName': r['bankName']!.trim(),
    }).where((r) => r['pattern']!.isNotEmpty && r['bankName']!.isNotEmpty).toList();

    await doc.set({'customHeaderBankRules': cleanedRules}, SetOptions(merge: true));

    // Retroactively update existing unassigned/unverified transactions in Firestore matching these pattern rules!
    try {
      final unassignedSnap = await doc.collection('sms_transactions').get();
      final batch = _db.batch();
      int updateCount = 0;

      for (final txDoc in unassignedSnap.docs) {
        final data = txDoc.data();
        final txSender = (data['sender'] ?? '').toString().trim().toUpperCase();
        final currentBank = (data['bankName'] ?? '').toString();

        if (txSender.isEmpty) continue;

        for (final rule in cleanedRules) {
          final p = rule['pattern']!;
          final b = rule['bankName']!;
          if (txSender.contains(p)) {
            if (currentBank == 'Bank' || currentBank.toLowerCase() == 'unknown' || currentBank != b) {
              batch.update(txDoc.reference, {'bankName': b});
              updateCount++;
            }
            break;
          }
        }
      }

      if (updateCount > 0) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Error applying custom header bank rules retroactively: $e');
    }
  }

  Future<void> addCustomHeaderBankRule(String pattern, String bankName) async {
    final p = pattern.trim().toUpperCase();
    final b = bankName.trim();
    if (p.isEmpty || b.isEmpty) return;

    final doc = _userDoc;
    if (doc == null) return;

    final snap = await doc.get();
    List<Map<String, String>> currentRules = [];
    if (snap.exists && snap.data() != null) {
      final data = snap.data() as Map<String, dynamic>;
      if (data.containsKey('customHeaderBankRules') && data['customHeaderBankRules'] is List) {
        final List<dynamic> list = data['customHeaderBankRules'];
        for (final item in list) {
          if (item is Map) {
            currentRules.add({
              'pattern': (item['pattern'] ?? '').toString().trim().toUpperCase(),
              'bankName': (item['bankName'] ?? '').toString().trim(),
            });
          }
        }
      }
    }

    currentRules.removeWhere((r) => r['pattern'] == p);
    currentRules.add({'pattern': p, 'bankName': b});

    await saveCustomHeaderBankRules(currentRules);
  }

  Future<void> deleteCustomHeaderBankRule(String pattern) async {
    final p = pattern.trim().toUpperCase();
    if (p.isEmpty) return;

    final doc = _userDoc;
    if (doc == null) return;

    final snap = await doc.get();
    List<Map<String, String>> currentRules = [];
    if (snap.exists && snap.data() != null) {
      final data = snap.data() as Map<String, dynamic>;
      if (data.containsKey('customHeaderBankRules') && data['customHeaderBankRules'] is List) {
        final List<dynamic> list = data['customHeaderBankRules'];
        for (final item in list) {
          if (item is Map) {
            currentRules.add({
              'pattern': (item['pattern'] ?? '').toString().trim().toUpperCase(),
              'bankName': (item['bankName'] ?? '').toString().trim(),
            });
          }
        }
      }
    }

    currentRules.removeWhere((r) => r['pattern'] == p);
    await saveCustomHeaderBankRules(currentRules);
  }

  // ============================================================================
  // USER CATEGORY BUDGETS (PERSISTENCE & SYNC)
  // ============================================================================

  Stream<Map<String, double>> getCategoryBudgetsStream() {
    final doc = _userDoc;
    if (doc == null) return Stream.value({});

    return doc.snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return {};
      final data = snap.data() as Map<String, dynamic>;
      final Map<String, dynamic> rawMap = data['categoryBudgets'] ?? {};
      final Map<String, double> result = {};
      rawMap.forEach((key, val) {
        if (val is num) {
          result[key] = val.toDouble();
        }
      });
      return result;
    });
  }

  Future<void> saveCategoryBudget(String category, double amount) async {
    final doc = _userDoc;
    if (doc == null) return;

    final snap = await doc.get();
    Map<String, dynamic> existingBudgets = {};
    if (snap.exists && snap.data() != null) {
      final data = snap.data() as Map<String, dynamic>;
      existingBudgets = Map<String, dynamic>.from(data['categoryBudgets'] ?? {});
    }

    if (amount <= 0) {
      existingBudgets.remove(category);
    } else {
      existingBudgets[category] = amount;
    }

    await doc.set({'categoryBudgets': existingBudgets}, SetOptions(merge: true));
  }
}
