import 'package:cloud_firestore/cloud_firestore.dart';

class BankAccount {
  final String id;
  final String name;
  final String accountType; // e.g. 'salary', 'savings', 'spending', 'cash', 'other'
  final double initialBalance;
  final double currentBalance;
  final int colorHex;
  final String iconName;
  final DateTime updatedAt;

  BankAccount({
    required this.id,
    required this.name,
    required this.accountType,
    required this.initialBalance,
    required this.currentBalance,
    required this.colorHex,
    required this.iconName,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'accountType': accountType,
      'initialBalance': initialBalance,
      'currentBalance': currentBalance,
      'colorHex': colorHex,
      'iconName': iconName,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory BankAccount.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedDate = DateTime.now();
    final updatedVal = map['updatedAt'];
    if (updatedVal is Timestamp) {
      parsedDate = updatedVal.toDate();
    } else if (updatedVal is String) {
      parsedDate = DateTime.tryParse(updatedVal) ?? DateTime.now();
    }

    return BankAccount(
      id: docId,
      name: map['name'] ?? 'Account',
      accountType: map['accountType'] ?? 'savings',
      initialBalance: (map['initialBalance'] as num?)?.toDouble() ?? 0.0,
      currentBalance: (map['currentBalance'] as num?)?.toDouble() ?? 0.0,
      colorHex: (map['colorHex'] as num?)?.toInt() ?? 0xFF2196F3,
      iconName: map['iconName'] ?? 'account_balance',
      updatedAt: parsedDate,
    );
  }

  BankAccount copyWith({
    String? name,
    String? accountType,
    double? initialBalance,
    double? currentBalance,
    int? colorHex,
    String? iconName,
    DateTime? updatedAt,
  }) {
    return BankAccount(
      id: id,
      name: name ?? this.name,
      accountType: accountType ?? this.accountType,
      initialBalance: initialBalance ?? this.initialBalance,
      currentBalance: currentBalance ?? this.currentBalance,
      colorHex: colorHex ?? this.colorHex,
      iconName: iconName ?? this.iconName,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
