/// Intelligent Expense Category Predictor for RemindBuddy.
/// Dynamically predicts the most likely financial category based on transaction
/// payee/merchant name, SMS content, UPI handles, and notification titles.
///
/// Designed to work universally for any user and any Indian / international merchants.
class ExpenseCategoryPredictor {
  static final RegExp _selfTransferRegex = RegExp(
    r'\b(self transfer|transfer to self|transfer to own|own account|linked account|to self a/c|from self a/c|cred club|cred\.club|credit card bill payment)\b',
    caseSensitive: false,
  );

  static final RegExp _foodAndDiningRegex = RegExp(
    r'\b(swiggy|zomato|eatclub|magicpin|dominos|pizza hut|mcdonalds|mcdonald|burger king|kfc|subway|starbucks|chai point|chaayos|haldiram|bikanervala|behrouz|faasos|ovenstory|freshmenu|barbeque nation|barbequenation|taco bell|popeyes|dunkin|restaurant|cafe|coffee|tea|chai|bakery|hotel|dining|bar|pub|brewery|eats|dhaba|bistro|pizza|burger|biryani|kitchen|mess|canteen|sweets|sweet mart|snacks|juice|shawarma|tiffin|roll|waffle|ice cream|dessert|pastry|lounge|grill|bbq|dosa|idli|meals|food court|buffet|fast food|tea stall|tea shop|chai shop|food corner|tiffin center|bhojanalaya|culinary|patisserie|sweets & chats|bhatura|pav bhaji)\b',
    caseSensitive: false,
  );

  static final RegExp _fuelAndTravelRegex = RegExp(
    r'\b(petrol|diesel|fuel|pump|indian oil|iocl|bpcl|hpcl|bharat petroleum|hindustan petroleum|shell|cng|nayara|reliance petroleum|fuel station|petrol bunk|rapido|uber|ola|namma metro|metro rail|delhi metro|irctc|indian railways|railway|train|flight|airline|airways|indigo|air india|akasa|spicejet|vistara|redbus|abhibus|bus stand|ksrtc|msrtc|apsrtc|bmtc|toll|fastag|nhai|parking|cab|taxi|auto rickshaw)\b',
    caseSensitive: false,
  );

  static final RegExp _groceriesRegex = RegExp(
    r"\b(zepto|blinkit|instamart|bigbasket|bbdaily|dunzo|dmart|d-mart|reliance smart|smart bazaar|nature'?s basket|more supermarket|spencer|spencers|star bazaar|jiomart|grocery|groceries|supermarket|kirana|provision|vegetable|vegetables|fruit|fruits|dairy|milk|nandini|amul|mother dairy|meat|fish|chicken|egg|organic store|general store|daily needs|ration|mandi)\b",
    caseSensitive: false,
  );

  static final RegExp _billsAndUtilitiesRegex = RegExp(
    r'\b(electricity|electric|power|bescom|tneb|msedcl|uppcl|cesc|tata power|torrent power|adani electricity|discom|bijli|water bill|water board|bwssb|indane|bharat gas|hp gas|piped gas|mgl|igl|adani gas|gas agency|recharge|mobile recharge|airtel|jio|vi |vodafone|bsnl|broadband|wifi|act fibernet|act corp|hathway|tata play|tatasky|tata sky|dth|dishtv|dish tv|sun direct|videocon d2h|rent|nobroker|society maintenance|maintenance charge|autopay|municipal|property tax|billdesk)\b',
    caseSensitive: false,
  );

  static final RegExp _shoppingRegex = RegExp(
    r'\b(amazon|flipkart|myntra|meesho|ajio|nykaa|tata cliq|tatacliq|tata neu|tataneu|snapdeal|purplle|zara|h&m|uniqlo|mango|trends|reliance trends|max fashion|pantaloons|westside|lifestyle|shoppers stop|decathlon|nike|adidas|puma|skechers|bata|croma|reliance digital|vijay sales|apple store|oneplus|ikea|urban ladder|pepperfry|lenskart|titan|tanishq|malabar gold|kalyan jewellers|shopping|apparel|clothing|clothes|boutique|fashion|shoes|footwear|jewel|jewellery|jewellers|electronics|gadgets|furniture|home decor|mall|retail)\b',
    caseSensitive: false,
  );

  static final RegExp _entertainmentRegex = RegExp(
    r'\b(netflix|spotify|amazon prime|prime video|hotstar|disney|apple music|gaana|wynk|jiocinema|sonyliv|zee5|youtube premium|youtube|bookmyshow|cinema|movies|movie|theatre|theater|pvr|inox|cinepolis|carnival cinemas|amusement|gaming|playstation|steam|xbox)\b',
    caseSensitive: false,
  );

  static final RegExp _medicalAndHealthRegex = RegExp(
    r'\b(pharmacy|chemist|medicals|medical store|apollo pharmacy|apollo 247|medplus|pharmeasy|1mg|netmeds|wellness forever|truemeds|hospital|clinic|doctor|dr |dr\.|dental|dentist|eye hospital|optical|lens|diagnostic|diagnostics|pathlab|lab|srl|dr lal|blood test|radiology|scan|consultation|health|healthcare|care hospital|fortis|manipal|narayana|max healthcare|gym|fitness|cult\.fit|cult fit|cultpass|yoga|crossfit)\b',
    caseSensitive: false,
  );

  static final RegExp _personalCareRegex = RegExp(
    r'\b(salon|spa|beauty parlour|beauty parlor|haircut|barber|hair styling|grooming|massage|skin care|skincare|cosmetics|makeup|nail art|tattoo|urban company|urbanclap)\b',
    caseSensitive: false,
  );

  static final RegExp _commercialTokenRegex = RegExp(
    r'\b(pvt|ltd|limited|enterprises?|store|mart|agency|agencies|solutions?|tech|technology|technologies|hospital|motors?|fuel|traders?|restaurant|cafe|station|bunk|services?|ventures?|llc|llp|corp|corporation|bank|inc|holdings?|works?|industries)\b',
    caseSensitive: false,
  );

  static final RegExp _personalVpaSuffixRegex = RegExp(
    r'@(okhdfcbank|okaxis|okicici|oksbi|paytm|ybl|axl|ibl|barodampay|federal|idfcbank|postbank|aubank|kotak)\b',
    caseSensitive: false,
  );

  /// Analyzes transaction metadata and returns the most suitable category.
  /// If unknown or untagged, returns 'Personal Transfer' for person payees, or 'Others'.
  static String predictCategory({
    required String payee,
    String? notes,
    String? rawBody,
    String? rawTitle,
  }) {
    final String combined = [
      payee,
      notes ?? '',
      rawBody ?? '',
      rawTitle ?? '',
    ].join(' ').trim().toLowerCase();

    if (combined.isEmpty) {
      return 'Others';
    }

    // 1. Self Transfer Check
    if (_selfTransferRegex.hasMatch(combined)) {
      return 'Self Transfer';
    }

    // 2. Food & Dining
    if (_foodAndDiningRegex.hasMatch(combined)) {
      return 'Food & Dining';
    }

    // 3. Fuel & Travel
    if (_fuelAndTravelRegex.hasMatch(combined)) {
      return 'Fuel & Travel';
    }

    // 4. Groceries
    if (_groceriesRegex.hasMatch(combined)) {
      return 'Groceries';
    }

    // 5. Bills & Utilities
    if (_billsAndUtilitiesRegex.hasMatch(combined)) {
      return 'Bills & Utilities';
    }

    // 6. Shopping
    if (_shoppingRegex.hasMatch(combined)) {
      return 'Shopping';
    }

    // 7. Entertainment
    if (_entertainmentRegex.hasMatch(combined)) {
      return 'Entertainment';
    }

    // 8. Medical & Health
    if (_medicalAndHealthRegex.hasMatch(combined)) {
      return 'Medical & Health';
    }

    // 9. Personal Care
    if (_personalCareRegex.hasMatch(combined)) {
      return 'Personal Care';
    }

    // 10. Personal Transfer Detection:
    // Check if payee appears to be a person's name or personal UPI ID
    if (_isLikelyPersonPayee(payee, combined)) {
      return 'Personal Transfer';
    }

    return 'Others';
  }

  /// Determines if the payee is likely an individual person rather than a merchant
  static bool _isLikelyPersonPayee(String payee, String combined) {
    final cleanPayee = payee.trim();
    if (cleanPayee.isEmpty) return false;

    // Check if there is a personal UPI handle in the text
    if (_personalVpaSuffixRegex.hasMatch(combined)) {
      return true;
    }

    // If payee has commercial keywords like Pvt Ltd, Store, etc., it's not a person
    if (_commercialTokenRegex.hasMatch(cleanPayee)) {
      return false;
    }

    // If combined text explicitly indicates personal transfer phrase
    if (combined.contains('transfer to') ||
        combined.contains('transferred to') ||
        combined.contains('sent to') ||
        combined.contains('paid to')) {
      return true;
    }

    // If payee consists of 1 to 4 clean alpha words (e.g. "Rahul Sharma", "Pooja V", "Amit")
    final words = cleanPayee.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isNotEmpty && words.length <= 4) {
      final bool allWordsAlpha = words.every((w) => RegExp(r'^[a-zA-Z\.\-]+$').hasMatch(w));
      if (allWordsAlpha && !cleanPayee.toLowerCase().contains('bank') && !cleanPayee.toLowerCase().contains('upi')) {
        return true;
      }
    }

    return false;
  }
}
