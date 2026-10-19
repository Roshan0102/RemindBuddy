import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiUsageInfo {
  final double used;
  final double limit;
  final String unit; // '$' for Apify, 'searches' or 'credits' for Tavily
  final String plan; // e.g. 'FREE', 'Researcher', etc.
  final bool isError;
  final String? errorMessage;
  final DateTime fetchedAt;

  const ApiUsageInfo({
    required this.used,
    required this.limit,
    required this.unit,
    required this.plan,
    this.isError = false,
    this.errorMessage,
    required this.fetchedAt,
  });

  double get percentage {
    if (limit <= 0) return 0.0;
    final pct = (used / limit) * 100;
    return pct.clamp(0.0, 100.0);
  }

  double get progressFraction {
    if (limit <= 0) return 0.0;
    final frac = used / limit;
    return frac.clamp(0.0, 1.0);
  }

  String get formattedUsed {
    if (unit == r'$') {
      return '\$${used.toStringAsFixed(2)}';
    }
    return used.toInt().toString();
  }

  String get formattedLimit {
    if (unit == r'$') {
      return '\$${limit.toStringAsFixed(2)}';
    }
    return limit.toInt().toString();
  }
}

class ApiUsageService {
  ApiUsageService._();
  static final ApiUsageService instance = ApiUsageService._();

  final Map<String, _CachedUsage> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// Fetches monthly usage for a given Tavily API key.
  Future<ApiUsageInfo> getTavilyUsage(String apiKey, {bool forceRefresh = false}) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      return ApiUsageInfo(
        used: 0,
        limit: 1000,
        unit: 'credits',
        plan: 'None',
        fetchedAt: DateTime.now(),
      );
    }

    final cacheKey = 'tavily_$cleanKey';
    if (!forceRefresh && _cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      if (DateTime.now().difference(cached.timestamp) < _cacheDuration) {
        return cached.data;
      }
    }

    try {
      final res = await http.get(
        Uri.parse('https://api.tavily.com/usage'),
        headers: {
          'Authorization': 'Bearer $cleanKey',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>? ?? {};
        final account = data['account'] as Map<String, dynamic>?;
        final keyInfo = data['key'] as Map<String, dynamic>?;

        final double planUsage = (account?['plan_usage'] as num?)?.toDouble() ??
            (keyInfo?['usage'] as num?)?.toDouble() ??
            0.0;
        final double planLimit = (account?['plan_limit'] as num?)?.toDouble() ?? 1000.0;
        final String planName = account?['current_plan']?.toString() ?? 'Free Plan';

        final info = ApiUsageInfo(
          used: planUsage,
          limit: planLimit,
          unit: 'credits',
          plan: planName,
          fetchedAt: DateTime.now(),
        );

        _cache[cacheKey] = _CachedUsage(info, DateTime.now());
        return info;
      } else if (res.statusCode == 401) {
        return ApiUsageInfo(
          used: 0,
          limit: 0,
          unit: 'credits',
          plan: 'Invalid Key',
          isError: true,
          errorMessage: 'Invalid Tavily API key (Unauthorized)',
          fetchedAt: DateTime.now(),
        );
      } else {
        return ApiUsageInfo(
          used: 0,
          limit: 0,
          unit: 'credits',
          plan: 'Error',
          isError: true,
          errorMessage: 'HTTP ${res.statusCode}',
          fetchedAt: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('[ApiUsageService] Error fetching Tavily usage: $e');
      return ApiUsageInfo(
        used: 0,
        limit: 0,
        unit: 'credits',
        plan: 'Offline',
        isError: true,
        errorMessage: 'Network error: $e',
        fetchedAt: DateTime.now(),
      );
    }
  }

  /// Fetches monthly usage credits and plan limit for an Apify API token.
  Future<ApiUsageInfo> getApifyUsage(String apiToken, {bool forceRefresh = false}) async {
    final cleanToken = apiToken.trim();
    if (cleanToken.isEmpty) {
      return ApiUsageInfo(
        used: 0,
        limit: 5.0,
        unit: r'$',
        plan: 'None',
        fetchedAt: DateTime.now(),
      );
    }

    final cacheKey = 'apify_$cleanToken';
    if (!forceRefresh && _cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      if (DateTime.now().difference(cached.timestamp) < _cacheDuration) {
        return cached.data;
      }
    }

    try {
      final headers = {
        'Authorization': 'Bearer $cleanToken',
        'Content-Type': 'application/json',
      };

      // Query plan information and monthly usage in parallel
      final results = await Future.wait([
        http.get(Uri.parse('https://api.apify.com/v2/users/me'), headers: headers).timeout(const Duration(seconds: 10)),
        http.get(Uri.parse('https://api.apify.com/v2/users/me/usage/monthly'), headers: headers).timeout(const Duration(seconds: 10)),
      ]);

      final userMeRes = results[0];
      final monthlyRes = results[1];

      if (userMeRes.statusCode == 401 || monthlyRes.statusCode == 401) {
        return ApiUsageInfo(
          used: 0,
          limit: 0,
          unit: r'$',
          plan: 'Invalid Token',
          isError: true,
          errorMessage: 'Invalid Apify API token',
          fetchedAt: DateTime.now(),
        );
      }

      if (userMeRes.statusCode == 200 && monthlyRes.statusCode == 200) {
        final userData = jsonDecode(userMeRes.body) as Map<String, dynamic>? ?? {};
        final monthlyData = jsonDecode(monthlyRes.body) as Map<String, dynamic>? ?? {};

        final planObj = (userData['data'] as Map<String, dynamic>?)?['plan'] as Map<String, dynamic>?;
        final monthlyPayload = monthlyData['data'] as Map<String, dynamic>? ?? {};

        final double limitUsd = (planObj?['monthlyUsageCreditsUsd'] as num?)?.toDouble() ??
            (planObj?['maxMonthlyUsageUsd'] as num?)?.toDouble() ??
            5.0;

        final double usedUsd = (monthlyPayload['totalUsageCreditsUsdAfterVolumeDiscount'] as num?)?.toDouble() ??
            (monthlyPayload['totalUsageCreditsUsd'] as num?)?.toDouble() ??
            0.0;

        final String planTier = planObj?['tier']?.toString() ?? planObj?['id']?.toString() ?? 'FREE';

        final info = ApiUsageInfo(
          used: usedUsd,
          limit: limitUsd,
          unit: r'$',
          plan: '$planTier Plan',
          fetchedAt: DateTime.now(),
        );

        _cache[cacheKey] = _CachedUsage(info, DateTime.now());
        return info;
      } else {
        return ApiUsageInfo(
          used: 0,
          limit: 5.0,
          unit: r'$',
          plan: 'Error',
          isError: true,
          errorMessage: 'Apify HTTP ${userMeRes.statusCode}',
          fetchedAt: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('[ApiUsageService] Error fetching Apify usage: $e');
      return ApiUsageInfo(
        used: 0,
        limit: 5.0,
        unit: r'$',
        plan: 'Offline',
        isError: true,
        errorMessage: 'Network error: $e',
        fetchedAt: DateTime.now(),
      );
    }
  }

  /// Invalidate cache for a specific key/token
  void invalidate(String keyOrToken) {
    _cache.remove('tavily_${keyOrToken.trim()}');
    _cache.remove('apify_${keyOrToken.trim()}');
  }
}

class _CachedUsage {
  final ApiUsageInfo data;
  final DateTime timestamp;

  _CachedUsage(this.data, this.timestamp);
}
