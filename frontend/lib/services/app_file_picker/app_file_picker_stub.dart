import 'app_file_picker.dart';

class AppFilePickerImpl {
  static Future<AppPickedFile?> pickImage({bool fromCamera = false}) =>
      throw UnimplementedError('AppFilePicker is not implemented on this platform.');

  static Future<List<AppPickedFile>> pickMultipleImages() =>
      throw UnimplementedError('AppFilePicker is not implemented on this platform.');

  static Future<AppPickedFile?> pickPdf() =>
      throw UnimplementedError('AppFilePicker is not implemented on this platform.');

  static Future<List<AppPickedFile>> pickFiles({
    List<String>? allowedExtensions,
    bool allowMultiple = true,
  }) =>
      throw UnimplementedError('AppFilePicker is not implemented on this platform.');
}
