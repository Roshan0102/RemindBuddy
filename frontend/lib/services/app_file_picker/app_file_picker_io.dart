import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'app_file_picker.dart';

class AppFilePickerImpl {
  static final ImagePicker _imagePicker = ImagePicker();

  static Future<AppPickedFile?> pickImage({bool fromCamera = false}) async {
    final XFile? file = await _imagePicker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return AppPickedFile(
      name: file.name,
      bytes: bytes,
      path: file.path,
      size: bytes.length,
    );
  }

  static Future<List<AppPickedFile>> pickMultipleImages() async {
    try {
      final List<XFile> files = await _imagePicker.pickMultiImage(imageQuality: 85);
      if (files.isNotEmpty) {
        final results = <AppPickedFile>[];
        for (final f in files) {
          final bytes = await f.readAsBytes();
          results.add(AppPickedFile(
            name: f.name,
            bytes: bytes,
            path: f.path,
            size: bytes.length,
          ));
        }
        return results;
      }
    } catch (_) {}

    // Fallback using FilePicker if pickMultiImage fails
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return [];

    final results = <AppPickedFile>[];
    for (final f in result.files) {
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
      if (bytes != null) {
        results.add(AppPickedFile(
          name: f.name,
          bytes: bytes,
          path: f.path,
          size: bytes.length,
        ));
      }
    }
    return results;
  }

  static Future<AppPickedFile?> pickPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;
    Uint8List? bytes = f.bytes;
    if (bytes == null && f.path != null) {
      bytes = await File(f.path!).readAsBytes();
    }
    if (bytes == null) return null;
    return AppPickedFile(
      name: f.name,
      bytes: bytes,
      path: f.path,
      size: bytes.length,
    );
  }

  static Future<List<AppPickedFile>> pickFiles({
    List<String>? allowedExtensions,
    bool allowMultiple = true,
  }) async {
    final result = await FilePicker.pickFiles(
      type: allowedExtensions != null ? FileType.custom : FileType.any,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return [];

    final results = <AppPickedFile>[];
    for (final f in result.files) {
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
      if (bytes != null) {
        results.add(AppPickedFile(
          name: f.name,
          bytes: bytes,
          path: f.path,
          size: bytes.length,
        ));
      }
    }
    return results;
  }
}
