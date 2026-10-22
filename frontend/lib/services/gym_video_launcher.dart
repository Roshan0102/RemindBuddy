import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'url_launcher_helper/url_launcher_helper.dart';

/// Helper to launch and inspect workout form videos across platforms
/// Supporting YouTube, Instagram Reels/Posts, and standard video/web links.
class GymVideoLauncher {
  /// Cleans and sanitizes the URL ensuring valid http/https scheme
  static String? sanitizeUrl(String? raw) {
    if (raw == null) return null;
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }

    try {
      final uri = Uri.parse(trimmed);
      if (uri.hasScheme && uri.host.isNotEmpty) {
        return trimmed;
      }
    } catch (_) {}
    return null;
  }

  /// Checks if URL is a YouTube link
  static bool isYouTube(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com') || lower.contains('youtu.be');
  }

  /// Checks if URL is an Instagram link
  static bool isInstagram(String url) {
    final lower = url.toLowerCase();
    return lower.contains('instagram.com') || lower.contains('instagr.am');
  }

  /// Returns an appropriate brand icon for the video platform
  static IconData getPlatformIcon(String? url) {
    if (url == null || url.isEmpty) return Icons.play_circle_outline;
    if (isYouTube(url)) return Icons.smart_display;
    if (isInstagram(url)) return Icons.camera_alt_outlined;
    return Icons.play_circle_fill;
  }

  /// Returns an appropriate color for the platform
  static Color getPlatformColor(String? url) {
    if (url == null || url.isEmpty) return Colors.blue;
    if (isYouTube(url)) return const Color(0xFFFF0000); // YouTube Red
    if (isInstagram(url)) return const Color(0xFFE1306C); // Instagram Pink/Purple
    return Colors.blueAccent;
  }

  /// Returns a human-readable platform label (e.g. "YouTube", "Instagram Reel", "Video")
  static String getPlatformLabel(String? url) {
    if (url == null || url.isEmpty) return 'Watch Video';
    if (isYouTube(url)) return 'Watch on YouTube';
    if (isInstagram(url)) return 'Watch on Instagram';
    return 'Watch Form Video';
  }

  /// Launches the video link:
  /// - On Mobile: launches in external app (opening native YouTube/Instagram app if installed)
  /// - On Web: uses programmatic anchor popup-bypass to open cleanly in new tab or trigger Universal Link
  static Future<bool> launchVideo(String rawUrl) async {
    final cleanUrl = sanitizeUrl(rawUrl);
    if (cleanUrl == null) return false;

    try {
      if (kIsWeb) {
        await UrlLauncherHelper.openInNewTabOrExternal(cleanUrl);
        return true;
      }

      final uri = Uri.parse(cleanUrl);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        // Fallback to in-app or platform default browser
        return await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      return launched;
    } catch (e) {
      debugPrint('GymVideoLauncher error launching $cleanUrl: $e');
      // Tertiary attempt via UrlLauncherHelper
      try {
        await UrlLauncherHelper.openInNewTabOrExternal(cleanUrl);
        return true;
      } catch (_) {
        return false;
      }
    }
  }
}
