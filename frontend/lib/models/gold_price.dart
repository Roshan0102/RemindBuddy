class GoldPrice {
  final String date; // YYYY-MM-DD format
  final double price22k; // 22 carat price per gram
  final double price24k; // 24 carat price per gram (optional)
  final String city; // Chennai, Mumbai, etc.

  GoldPrice({
    required this.date,
    required this.price22k,
    this.price24k = 0.0,
    this.city = 'Chennai',
  });

  factory GoldPrice.fromJson(Map<String, dynamic> json) {
    return GoldPrice(
      date: json['date'],
      price22k: (json['price22k'] as num).toDouble(),
      price24k: json['price24k'] != null ? (json['price24k'] as num).toDouble() : 0.0,
      city: json['city'] ?? 'Chennai',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'price22k': price22k,
      'price24k': price24k,
      'city': city,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'price22k': price22k,
      'price24k': price24k,
      'city': city,
    };
  }

  // Calculate price change from previous day
  double getPriceChange(GoldPrice previousDay) {
    return price22k - previousDay.price22k;
  }

  // Get percentage change
  double getPercentageChange(GoldPrice previousDay) {
    if (previousDay.price22k == 0) return 0.0;
    return ((price22k - previousDay.price22k) / previousDay.price22k) * 100;
  }
}
