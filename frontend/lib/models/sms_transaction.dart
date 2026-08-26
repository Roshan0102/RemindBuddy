class SmsTransaction {
  final String id;
  final String sender;
  final String bankName;
  final String accountLast4;
  final String type; // 'Debit' or 'Credit'
  final double amount;
  final String payee;
  final DateTime timestamp;
  final bool isVerified;
  final String category;
  final String notes;

  SmsTransaction({
    required this.id,
    this.sender = '',
    required this.bankName,
    required this.accountLast4,
    required this.type,
    required this.amount,
    required this.payee,
    required this.timestamp,
    this.isVerified = false,
    this.category = 'Uncategorized',
    this.notes = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender': sender,
      'bankName': bankName,
      'accountLast4': accountLast4,
      'type': type,
      'amount': amount,
      'payee': payee,
      'timestamp': timestamp.toIso8601String(),
      'isVerified': isVerified,
      'category': category,
      'notes': notes,
    };
  }

  factory SmsTransaction.fromMap(Map<String, dynamic> map) {
    return SmsTransaction(
      id: map['id'] ?? '',
      sender: map['sender'] ?? '',
      bankName: map['bankName'] ?? 'Bank',
      accountLast4: map['accountLast4'] ?? '',
      type: map['type'] ?? 'Debit',
      amount: (map['amount'] is num) ? (map['amount'] as num).toDouble() : 0.0,
      payee: map['payee'] ?? 'Unknown Payee',
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isVerified: map['isVerified'] ?? false,
      category: map['category'] ?? 'Uncategorized',
      notes: map['notes'] ?? '',
    );
  }

  SmsTransaction copyWith({
    String? id,
    String? sender,
    String? bankName,
    String? accountLast4,
    String? type,
    double? amount,
    String? payee,
    DateTime? timestamp,
    bool? isVerified,
    String? category,
    String? notes,
  }) {
    return SmsTransaction(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      bankName: bankName ?? this.bankName,
      accountLast4: accountLast4 ?? this.accountLast4,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      payee: payee ?? this.payee,
      timestamp: timestamp ?? this.timestamp,
      isVerified: isVerified ?? this.isVerified,
      category: category ?? this.category,
      notes: notes ?? this.notes,
    );
  }
}
