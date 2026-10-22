import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'url_launcher_helper/url_launcher_helper.dart';

class DownloadResult {
  final bool isSuccess;
  final String? filePath;
  final String? fileName;
  final String? errorMessage;

  DownloadResult({
    required this.isSuccess,
    this.filePath,
    this.fileName,
    this.errorMessage,
  });
}

class FileDownloadService {
  static const MethodChannel _channel = MethodChannel('com.remindbuddy/file_downloader');

  /// Saves a file directly to the device's public Downloads directory.
  /// - On Android: Uses MediaStore.Downloads (Android 10+) or Environment directory (Android 9-)
  /// - On Web: Triggers browser download anchor
  /// - On iOS / Desktop: Uses application documents or downloads directory
  static Future<DownloadResult> saveFile({
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'application/pdf',
  }) async {
    final cleanFileName = fileName.trim().isNotEmpty
        ? fileName.trim()
        : 'SmartBuddy_Document.pdf';

    if (kIsWeb) {
      final base64Str = base64Encode(bytes);
      UrlLauncherHelper.downloadBase64(base64Str, cleanFileName, mimeType: mimeType);
      return DownloadResult(isSuccess: true, fileName: cleanFileName);
    }

    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<Map>('saveToDownloads', {
          'bytes': bytes,
          'fileName': cleanFileName,
          'mimeType': mimeType,
        });
        if (result != null && result['success'] == true) {
          return DownloadResult(
            isSuccess: true,
            filePath: result['path']?.toString(),
            fileName: cleanFileName,
          );
        }
      } catch (e) {
        debugPrint('FileDownloadService native Android save error: $e');
      }
    }

    // Fallback for iOS / macOS / Windows / Linux or Android fallback
    try {
      Directory? downloadsDir;
      try {
        downloadsDir = await getDownloadsDirectory();
      } catch (_) {}
      downloadsDir ??= await getApplicationDocumentsDirectory();

      final safeName = cleanFileName.replaceAll(RegExp(r'[^\w\-_.]'), '_');
      final file = File('${downloadsDir.path}/$safeName');
      await file.writeAsBytes(bytes);

      return DownloadResult(
        isSuccess: true,
        filePath: file.path,
        fileName: safeName,
      );
    } catch (e) {
      return DownloadResult(isSuccess: false, errorMessage: e.toString());
    }
  }
}
