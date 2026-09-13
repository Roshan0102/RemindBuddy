import 'dart:typed_data';

class WebClipboardDragService {
  static void initListeners({
    required void Function(Uint8List bytes, String name) onImageReceived,
    required bool Function() isActive,
  }) {
    // Native mobile/desktop listener no-op (use file picker or keyboard listener)
  }

  static void disposeListeners() {
    // No-op on native IO
  }

  static Future<Uint8List?> readImageFromClipboard() async {
    return null;
  }
}
