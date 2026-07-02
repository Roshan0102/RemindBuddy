import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/Roshan0102/RemindBuddy/releases/latest';

  /// Checks for updates. If a new version is available, it pops up an update dialog.
  static Future<void> checkForUpdates(BuildContext context, {bool showNoUpdateMsg = false}) async {
    try {
      // 1. Get current version of the app
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version; // e.g. "1.5.2"

      // 2. Fetch the latest release metadata from GitHub
      final response = await http.get(Uri.parse(_latestReleaseUrl));
      if (response.statusCode != 200) {
        debugPrint('Failed to fetch latest release: ${response.statusCode}');
        return;
      }

      final Map<String, dynamic> data = json.decode(response.body);
      final String latestTag = data['tag_name'] ?? ''; // e.g. "v1.5.3"
      if (latestTag.isEmpty) return;

      // 3. Find the APK asset download URL
      String downloadUrl = '';
      final List<dynamic> assets = data['assets'] ?? [];
      for (var asset in assets) {
        if (asset['name'] != null && asset['name'].toString().endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] ?? '';
          break;
        }
      }

      if (downloadUrl.isEmpty) {
        debugPrint('No APK asset found in the latest release.');
        return;
      }

      // 4. Compare versions
      final bool updateAvailable = _isNewerVersion(currentVersion, latestTag);

      if (updateAvailable) {
        if (context.mounted) {
          _showUpdateDialog(context, latestTag.replaceAll('v', ''), downloadUrl);
        }
      } else if (showNoUpdateMsg) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your app is up to date!')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
    }
  }

  /// Helper to compare semantic versions: returns true if latestVersion > currentVersion
  static bool _isNewerVersion(String currentVersion, String latestVersion) {
    final cleanLatest = latestVersion.replaceAll(RegExp(r'[^\d.]'), '');
    final cleanCurrent = currentVersion.replaceAll(RegExp(r'[^\d.]'), '');

    if (cleanLatest.isEmpty || cleanCurrent.isEmpty) return false;

    List<int> latestParts = cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> currentParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    int maxLength = latestParts.length > currentParts.length ? latestParts.length : currentParts.length;

    for (int i = 0; i < maxLength; i++) {
      int latestPart = i < latestParts.length ? latestParts[i] : 0;
      int currentPart = i < currentParts.length ? currentParts[i] : 0;

      if (latestPart > currentPart) return true;
      if (latestPart < currentPart) return false;
    }
    return false;
  }

  /// Displays the update dialog card
  static void _showUpdateDialog(BuildContext context, String newVersion, String downloadUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.system_update_alt, color: Colors.deepPurple, size: 28),
              SizedBox(width: 10),
              Text('Update Available!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new version of RemindBuddy (v$newVersion) is available.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please update to get the latest features, security patches, and bug fixes.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final Uri url = Uri.parse(downloadUrl);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not open browser to download the update.')),
                    );
                  }
                }
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Update Now'),
            ),
          ],
        );
      },
    );
  }
}
