import 'package:url_launcher/url_launcher.dart';

Future<void> openExternalUrl(String url) async {
  final cleanUrl = url.trim();
  if (cleanUrl.isEmpty) return;
  final uri = Uri.tryParse(cleanUrl);
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
