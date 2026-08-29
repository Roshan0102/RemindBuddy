import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/services/upi_notification_parser_service.dart';

void main() {
  group('UpiNotificationParserService Tests', () {
    test('Correctly parses GPay received payment notification', () {
      final tx = UpiNotificationParserService.parseNotification(
        packageName: 'com.google.android.apps.npx',
        appName: 'GPay',
        title: 'Payment received',
        body: 'Rahul Sharma paid you ₹500.00',
        timestampMillis: 1724938200000,
      );

      expect(tx, isNotNull);
      expect(tx!.amount, 500.0);
      expect(tx.type, 'Credit');
      expect(tx.payee, 'Rahul Sharma');
      expect(tx.bankName, 'GPay');
      expect(tx.source, 'notification');
      expect(tx.sourceApp, 'GPay');
    });

    test('Correctly parses GPay paid/debit payment notification', () {
      final tx = UpiNotificationParserService.parseNotification(
        packageName: 'com.google.android.apps.npx',
        appName: 'GPay',
        title: 'Google Pay',
        body: 'You paid ₹150 to Chai Point using HDFC Bank',
        timestampMillis: 1724938300000,
      );

      expect(tx, isNotNull);
      expect(tx!.amount, 150.0);
      expect(tx.type, 'Debit');
      expect(tx.payee, 'Chai Point');
      expect(tx.sourceApp, 'GPay');
    });

    test('Correctly parses PhonePe credit notification with UTR', () {
      final tx = UpiNotificationParserService.parseNotification(
        packageName: 'com.phonepe.app',
        appName: 'PhonePe',
        title: 'Money Received',
        body: 'Received ₹2,000 from Priya Patel. UPI Ref: 424109481923',
        timestampMillis: 1724938400000,
      );

      expect(tx, isNotNull);
      expect(tx!.amount, 2000.0);
      expect(tx.type, 'Credit');
      expect(tx.payee, 'Priya Patel');
      expect(tx.upiRef, '424109481923');
      expect(tx.sourceApp, 'PhonePe');
    });

    test('Correctly parses Paytm debit notification', () {
      final tx = UpiNotificationParserService.parseNotification(
        packageName: 'net.one97.paytm',
        appName: 'Paytm',
        title: 'Paid Successfully',
        body: 'Paid ₹450 to Swiggy was successful.',
        timestampMillis: 1724938500000,
      );

      expect(tx, isNotNull);
      expect(tx!.amount, 450.0);
      expect(tx.type, 'Debit');
      expect(tx.payee, 'Swiggy');
      expect(tx.sourceApp, 'Paytm');
    });

    test('Correctly parses Super.money credit notification', () {
      final tx = UpiNotificationParserService.parseNotification(
        packageName: 'in.super.money',
        appName: 'Super.money',
        title: 'super.money UPI',
        body: '₹350 received from Anand K via super.money',
        timestampMillis: 1724938600000,
      );

      expect(tx, isNotNull);
      expect(tx!.amount, 350.0);
      expect(tx.type, 'Credit');
      expect(tx.payee, 'Anand K');
      expect(tx.sourceApp, 'Super.money');
    });

    test('Correctly parses CRED payment notification', () {
      final tx = UpiNotificationParserService.parseNotification(
        packageName: 'com.dreamplug.androidapp',
        appName: 'CRED',
        title: 'CRED Pay',
        body: 'Paid ₹1,200 for Electricity Bill',
        timestampMillis: 1724938700000,
      );

      expect(tx, isNotNull);
      expect(tx!.amount, 1200.0);
      expect(tx.type, 'Debit');
      expect(tx.sourceApp, 'CRED');
    });

    test('Ignores promotional and spam notifications', () {
      final tx = UpiNotificationParserService.parseNotification(
        packageName: 'com.phonepe.app',
        appName: 'PhonePe',
        title: 'Cashback Won!',
        body: 'Scratch card unlocked! Flat ₹50 off on your next recharge.',
        timestampMillis: 1724938800000,
      );

      expect(tx, isNull);
    });
  });
}
