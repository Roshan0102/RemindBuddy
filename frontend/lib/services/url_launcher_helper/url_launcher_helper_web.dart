// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openExternalUrl(String url) async {
  final cleanUrl = url.trim();
  if (cleanUrl.isEmpty) return;

  bool openedSuccessfully = false;

  // 1. Primary approach for Web: Programmatic Anchor Element click with target="_blank"
  // This simulates a native hyperlink click and successfully bypasses browser popup blockers
  // on Desktop Chrome/Safari and Mobile iPhone Safari / Chrome.
  try {
    final anchor = html.AnchorElement(href: cleanUrl)
      ..target = '_blank'
      ..rel = 'noopener noreferrer'
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    openedSuccessfully = true;
  } catch (e) {
    debugPrint('Anchor element click failed on web: $e');
  }

  // 2. Secondary fallback: html.window.open
  if (!openedSuccessfully) {
    try {
      html.window.open(cleanUrl, '_blank');
      openedSuccessfully = true;
    } catch (e) {
      debugPrint('html.window.open failed on web: $e');
    }
  }

  // 3. Tertiary fallback: url_launcher externalApplication
  if (!openedSuccessfully) {
    try {
      final uri = Uri.tryParse(cleanUrl);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
      }
    } catch (e) {
      debugPrint('url_launcher fallback failed on web: $e');
    }
  }
}

void downloadBase64File(String cleanBase64, String filename, String mimeType) {
  try {
    final bytes = base64Decode(cleanBase64);
    final blob = html.Blob([bytes], mimeType);
    final blobUrl = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: blobUrl)
      ..setAttribute('download', filename)
      ..style.display = 'none';
    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    Future.delayed(const Duration(seconds: 15), () {
      try {
        html.Url.revokeObjectUrl(blobUrl);
      } catch (_) {}
    });
  } catch (e) {
    debugPrint('Blob download failed on web, falling back to dataUrl: $e');
    try {
      final dataUrl = 'data:$mimeType;base64,$cleanBase64';
      final anchor = html.AnchorElement(href: dataUrl)
        ..setAttribute('download', filename)
        ..style.display = 'none';
      html.document.body?.children.add(anchor);
      anchor.click();
      anchor.remove();
    } catch (err) {
      debugPrint('Anchor fallback download failed on web: $err');
    }
  }
}
