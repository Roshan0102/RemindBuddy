import 'dart:typed_data';

class WebClipboardDragService {
  static void initListeners({
    required void Function(Uint8List bytes, String name) onImageReceived,
    required bool Function() isActive,
  }) {
    // No-op on stub
  }

  static void disposeListeners() {
    // No-op on stub
  }

  static Future<Uint8List?> readImageFromClipboard() async {
    return null;
  }
}
