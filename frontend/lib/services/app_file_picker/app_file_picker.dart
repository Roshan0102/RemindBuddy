import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

import 'app_file_picker_stub.dart'
    if (dart.library.html) 'app_file_picker_web.dart'
    if (dart.library.io) 'app_file_picker_io.dart';

class AppPickedFile {
  final String name;
  final Uint8List bytes;
  final String? path;
  final int size;

  const AppPickedFile({
    required this.name,
    required this.bytes,
    this.path,
    required this.size,
  });

  XFile toXFile() => XFile.fromData(bytes, name: name, path: path);
}

class AppFilePicker {
  /// Picks a single image from gallery (or camera if requested).
  /// Opens the native OS file manager / photo chooser across Web, Ubuntu, macOS, Windows, Android, and iOS.
  static Future<AppPickedFile?> pickImage({bool fromCamera = false}) =>
      AppFilePickerImpl.pickImage(fromCamera: fromCamera);

  /// Picks multiple images.
  static Future<List<AppPickedFile>> pickMultipleImages() =>
      AppFilePickerImpl.pickMultipleImages();

  /// Picks a single PDF document.
  static Future<AppPickedFile?> pickPdf() =>
      AppFilePickerImpl.pickPdf();

  /// Picks one or more general files with optional extension filters.
  static Future<List<AppPickedFile>> pickFiles({
    List<String>? allowedExtensions,
    bool allowMultiple = true,
  }) =>
      AppFilePickerImpl.pickFiles(
        allowedExtensions: allowedExtensions,
        allowMultiple: allowMultiple,
      );
}
