import 'package:flutter/material.dart';
import '../services/api_usage_service.dart';

enum ApiProviderType {
  tavily,
  apify,
}

class ApiUsageLineIndicator extends StatefulWidget {
  final ApiProviderType providerType;
  final String apiKey;
  final EdgeInsetsGeometry padding;

  const ApiUsageLineIndicator({
    super.key,
    required this.providerType,
    required this.apiKey,
    this.padding = const EdgeInsets.only(top: 6, bottom: 8),
  });

  @override
  State<ApiUsageLineIndicator> createState() => _ApiUsageLineIndicatorState();
}

class _ApiUsageLineIndicatorState extends State<ApiUsageLineIndicator> {
  ApiUsageInfo? _usageInfo;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchUsage();
  }

  @override
  void didUpdateWidget(covariant ApiUsageLineIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiKey.trim() != widget.apiKey.trim()) {
      _fetchUsage();
    }
  }

  Future<void> _fetchUsage({bool forceRefresh = false}) async {
    final key = widget.apiKey.trim();
    if (key.isEmpty || key.length < 5) {
      if (mounted) {
        setState(() {
          _usageInfo = null;
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    ApiUsageInfo info;
    if (widget.providerType == ApiProviderType.tavily) {
      info = await ApiUsageService.instance.getTavilyUsage(key, forceRefresh: forceRefresh);
    } else {
      info = await ApiUsageService.instance.getApifyUsage(key, forceRefresh: forceRefresh);
    }

    if (mounted) {
      setState(() {
        _usageInfo = info;
        _isLoading = false;
      });
    }
  }

  Color _getStatusColor(double pct) {
    if (pct >= 90.0) return const Color(0xFFEF4444); // Red
    if (pct >= 70.0) return const Color(0xFFF59E0B); // Amber
    return const Color(0xFF10B981); // Emerald
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.apiKey.trim();
    if (key.isEmpty || key.length < 5) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final neutralBg = isDark ? Colors.white12 : Colors.grey.shade200;

    if (_isLoading && _usageInfo == null) {
      return Padding(
        padding: widget.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: neutralBg,
                valueColor: AlwaysStoppedAnimation<Color>(
                  widget.providerType == ApiProviderType.tavily ? Colors.teal : const Color(0xFF0A66C2),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Checking monthly usage...',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    final info = _usageInfo;
    if (info == null) return const SizedBox.shrink();

    if (info.isError) {
      return Padding(
        padding: widget.padding,
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, size: 14, color: Color(0xFFEF4444)),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                info.errorMessage ?? 'Unable to verify quota',
                style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _fetchUsage(forceRefresh: true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 13, color: isDark ? Colors.white70 : Colors.grey.shade700),
                    const SizedBox(width: 3),
                    Text(
                      'Retry',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final pct = info.percentage;
    final statusColor = _getStatusColor(pct);

    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress bar line
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: info.progressFraction,
              minHeight: 5,
              backgroundColor: neutralBg,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: 5),
          // Info row
          Row(
            children: [
              // Status dot
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              // Usage text
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white70 : Colors.grey.shade800,
                    ),
                    children: [
                      const TextSpan(text: 'Used: '),
                      TextSpan(
                        text: info.formattedUsed,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      TextSpan(text: ' / ${info.formattedLimit} ${info.unit} ('),
                      TextSpan(
                        text: '${pct.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                      const TextSpan(text: ' this month)'),
                    ],
                  ),
                ),
              ),
              // Plan tag & refresh button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  info.plan,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _isLoading ? null : () => _fetchUsage(forceRefresh: true),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: _isLoading
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: statusColor),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          size: 14,
                          color: isDark ? Colors.white54 : Colors.grey.shade600,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
