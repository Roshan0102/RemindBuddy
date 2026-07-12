import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ota_update/ota_update.dart';

class UpdateService {
  /// Checks for updates. If a new version is available, it pops up an update dialog.
  static Future<void> checkForUpdates(BuildContext context, {bool showNoUpdateMsg = false}) async {
    if (kIsWeb) return; // Never show APK updates on the web

    try {
      // 1. Get current version of the app
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      // 2. Fetch version config from Firestore
      final configDoc = await FirebaseFirestore.instance.collection('admin_creds').doc('app_updates').get();
      
      String targetVersion = currentVersion;
      
      if (configDoc.exists && configDoc.data() != null) {
        final data = configDoc.data()!;
        final stableVersion = data['latest_stable_version'] as String? ?? currentVersion;
        List<dynamic> betaUids = data['beta_tester_uids'] ?? [];
        
        // Find if current user is a beta tester
        final user = FirebaseAuth.instance.currentUser;
        bool isBetaTester = false;
        if (user != null) {
          if (betaUids.contains(user.uid)) {
            isBetaTester = true;
          }
        }
        
        if (isBetaTester) {
          // Beta testers automatically fetch the latest release from GitHub
          final latestGitTag = await fetchLatestGitHubTag();
          targetVersion = latestGitTag.isNotEmpty ? latestGitTag : (data['latest_beta_version'] as String? ?? currentVersion);
          
          // Also automatically keep Firestore updated with this beta version so Admin Screen can read it
          if (latestGitTag.isNotEmpty && latestGitTag != data['latest_beta_version']) {
            FirebaseFirestore.instance.collection('admin_creds').doc('app_updates').update({
              'latest_beta_version': latestGitTag,
            }).catchError((_) {});
          }
        } else {
          targetVersion = stableVersion;
        }
      }

      // 3. Compare versions
      final bool updateAvailable = _isNewerVersion(currentVersion, targetVersion);

      if (updateAvailable) {
        // 4. Fetch the specific release metadata from GitHub to get the download URL
        final String releaseUrl = 'https://api.github.com/repos/Roshan0102/RemindBuddy/releases/tags/v$targetVersion';
        final response = await http.get(Uri.parse(releaseUrl));
        
        if (response.statusCode == 200) {
          final Map<String, dynamic> data = json.decode(response.body);
          String downloadUrl = '';
          final List<dynamic> assets = data['assets'] ?? [];
          for (var asset in assets) {
            if (asset['name'] != null && asset['name'].toString().endsWith('.apk')) {
              downloadUrl = asset['browser_download_url'] ?? '';
              break;
            }
          }
          
          if (downloadUrl.isNotEmpty && context.mounted) {
            _showUpdateDialog(context, targetVersion, downloadUrl);
            return;
          }
        }
      } 
      
      if (showNoUpdateMsg) {
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

  /// Fetches the latest tag name from GitHub releases
  static Future<String> fetchLatestGitHubTag() async {
    try {
      final response = await http.get(Uri.parse('https://api.github.com/repos/Roshan0102/RemindBuddy/releases/latest'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final String tag = data['tag_name'] ?? '';
        return tag.replaceAll('v', '');
      }
    } catch (e) {
      debugPrint('Error fetching latest GitHub release: $e');
    }
    return '';
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
        return OtaUpdateDialog(newVersion: newVersion, downloadUrl: downloadUrl);
      },
    );
  }
}

class OtaUpdateDialog extends StatefulWidget {
  final String newVersion;
  final String downloadUrl;

  const OtaUpdateDialog({
    super.key,
    required this.newVersion,
    required this.downloadUrl,
  });

  @override
  State<OtaUpdateDialog> createState() => _OtaUpdateDialogState();
}

class _OtaUpdateDialogState extends State<OtaUpdateDialog> {
  bool _isDownloading = false;
  String _progress = '0';
  String _statusMessage = '';
  StreamSubscription? _otaSubscription;

  @override
  void dispose() {
    _otaSubscription?.cancel();
    super.dispose();
  }

  void _startDownload() {
    setState(() {
      _isDownloading = true;
      _statusMessage = 'Downloading update...';
    });

    try {
      _otaSubscription = OtaUpdate().execute(
        widget.downloadUrl,
        destinationFilename: 'remindbuddy_${widget.newVersion}.apk',
      ).listen(
        (OtaEvent event) {
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              setState(() {
                _progress = event.value ?? '0';
                _statusMessage = 'Downloading update: $_progress%';
              });
              break;
            case OtaStatus.INSTALLING:
              setState(() {
                _statusMessage = 'Launching installer...';
              });
              if (mounted) {
                Navigator.of(context).pop(); // Close dialog on launch installer
              }
              break;
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              setState(() {
                _isDownloading = false;
                _statusMessage = 'Permission not granted to install unknown apps.';
              });
              break;
            case OtaStatus.DOWNLOAD_ERROR:
            case OtaStatus.INTERNAL_ERROR:
              setState(() {
                _isDownloading = false;
                _statusMessage = 'Failed to download the update.';
              });
              break;
            default:
              break;
          }
        },
        onError: (err) {
          setState(() {
            _isDownloading = false;
            _statusMessage = 'Error during update: $err';
          });
        },
      );
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _statusMessage = 'Failed to start update: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.system_update_alt, color: Colors.deepPurple, size: 28),
          const SizedBox(width: 10),
          Expanded(child: Text(_isDownloading ? 'Downloading Update' : 'Update to v${widget.newVersion} Available!')),
        ],
      ),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_isDownloading) ...[
              Text(
                'A new version (v${widget.newVersion}) of RemindBuddy is ready to install.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please update to get the latest features, security patches, and bug fixes.',
              ),
              if (_statusMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _statusMessage,
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                ),
              ],
            ] else ...[
              Text(_statusMessage),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: double.tryParse(_progress) != null ? double.parse(_progress) / 100 : 0.0,
                backgroundColor: Colors.grey.shade300,
                color: Colors.deepPurple,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$_progress%',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: _isDownloading
          ? []
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Later', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: _startDownload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Update Now'),
              ),
            ],
    );
  }
}
