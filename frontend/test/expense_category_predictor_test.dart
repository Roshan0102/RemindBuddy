import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/services/expense_category_predictor.dart';

void main() {
  group('ExpenseCategoryPredictor Tests', () {
    test('Shopping Detection', () {
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Myntra Designs', rawBody: 'Paid Rs 1499 to Myntra'),
        equals('Shopping'),
      );
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Amazon India', rawBody: 'Debited for Amazon Pay'),
        equals('Shopping'),
      );
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Ajio Retail', rawBody: 'Payment to Ajio successful'),
        equals('Shopping'),
      );
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Zara Store', rawBody: 'Spent Rs 3290 at Zara'),
        equals('Shopping'),
      );
    });

    test('Food & Dining Detection', () {
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Swiggy', rawBody: 'Paid Rs 340 to Swiggy'),
        equals('Food & Dining'),
      );
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Chai Point', rawBody: 'Payment to Chai Point at Indiranagar'),
        equals('Food & Dining'),
      );
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Corner House', rawBody: 'Paid to Corner House Ice Cream'),
        equals('Food & Dining'),
      );
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Bawarchi Restaurant', rawBody: 'Debited Rs 850 at Bawarchi Restaurant'),
        equals('Food & Dining'),
      );
    });

    test('Fuel & Travel Detection', () {
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Indian Oil Petrol Pump', rawBody: 'Paid at IOCL petrol bunk'),
        equals('Fuel & Travel'),
      );
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Shell Fuel Station', rawBody: 'Spent Rs 2000 at Shell'),
        equals('Fuel & Travel'),
      );
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Uber India', rawBody: 'Paid Rs 240 for Uber trip'),
        equals('Fuel & Travel'),
      );
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Rapido Bike Taxi', rawBody: 'Auto debit for Rapido'),
        equals('Fuel & Travel'),
      );
    });

    test('Groceries Detection', () {
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Zepto', rawBody: 'Paid Rs 410 to Zepto'),
        equals('Groceries'),
      );
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Blinkit Commerce', rawBody: 'Paid Rs 530 to Blinkit'),
        equals('Groceries'),
      );
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Nandini Milk Parlour', rawBody: 'Paid Rs 54 at Nandini'),
        equals('Groceries'),
      );
    });

    test('Bills & Utilities Detection', () {
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'BESCOM Electricity', rawBody: 'Electricity bill paid Rs 1400'),
        equals('Bills & Utilities'),
      );
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Airtel Prepaid', rawBody: 'Recharge successful for Airtel 9876543210'),
        equals('Bills & Utilities'),
      );
    });

    test('Personal Transfer Detection', () {
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Rahul Sharma', rawBody: 'Paid to Rahul Sharma at rahul@okhdfcbank'),
        equals('Personal Transfer'),
      );
      expect(
        ExpenseCategoryPredictor.predictCategory(payee: 'Pooja V', rawBody: 'Sent Rs 500 to Pooja V'),
        equals('Personal Transfer'),
      );
    });
  });
}
