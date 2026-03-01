class GoldPrice {
  final int? id;
  final String date; // YYYY-MM-DD
  final String timestamp; // ISO format or formatted time representing exact fetch
  final double price;
  final double priceChange;
  final String? remoteId;
  final bool isSynced;
  final String? updatedAt;

  GoldPrice({
    this.id,
    required this.date,
    required this.timestamp,
    required this.price,
    this.priceChange = 0.0,
    this.remoteId,
    this.isSynced = false,
    this.updatedAt,
  });

  factory GoldPrice.fromJson(Map<String, dynamic> json) {
    return GoldPrice(
      id: json['id'],
      date: json['date'],
      timestamp: json['timestamp'] ?? json['date'], // fallback
      price: json['price'] != null ? (json['price'] as num).toDouble() : (json['price22k'] != null ? (json['price22k'] as num).toDouble() : 0.0),
      priceChange: json['priceChange'] != null ? (json['priceChange'] as num).toDouble() : (json['price_change'] != null ? (json['price_change'] as num).toDouble() : 0.0),
      remoteId: json['remoteId'],
      isSynced: json['isSynced'] == 1 || json['isSynced'] == true,
      updatedAt: json['updatedAt'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date,
      'timestamp': timestamp,
      'price': price,
      'priceChange': priceChange,
      'remoteId': remoteId,
      'isSynced': isSynced,
      'updatedAt': updatedAt,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'timestamp': timestamp,
      'price': price,
      'priceChange': priceChange,
      'remoteId': remoteId,
      'isSynced': isSynced ? 1 : 0,
      'updatedAt': updatedAt ?? DateTime.now().toIso8601String(),
    };
  }
}

