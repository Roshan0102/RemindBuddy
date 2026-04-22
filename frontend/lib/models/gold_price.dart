class GoldPrice {
  final String? id; // Firestore document ID (String)
  final String date; // YYYY-MM-DD
  final String timestamp; // ISO format or formatted time representing exact fetch
  final double price;
  final double priceChange;
  final String source;

  GoldPrice({
    this.id,
    required this.date,
    required this.timestamp,
    required this.price,
    this.priceChange = 0.0,
    this.source = 'Unknown',
  });

  factory GoldPrice.fromJson(Map<String, dynamic> json, [String? id]) {
    return GoldPrice(
      id: id ?? json['id']?.toString(),
      date: json['date'],
      timestamp: json['timestamp'] ?? json['date'], // fallback
      price: json['price'] != null ? (json['price'] as num).toDouble() : (json['price22k'] != null ? (json['price22k'] as num).toDouble() : 0.0),
      priceChange: json['priceChange'] != null ? (json['priceChange'] as num).toDouble() : (json['price_change'] != null ? (json['price_change'] as num).toDouble() : 0.0),
      source: json['source'] ?? 'Unknown',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'timestamp': timestamp,
      'price': price,
      'priceChange': priceChange,
      'source': source,
    };
  }

  Map<String, dynamic> toMap() => toJson();
}
