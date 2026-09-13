import 'dart:typed_data';

import 'web_clipboard_drag_stub.dart'
    if (dart.library.html) 'web_clipboard_drag_web.dart'
    if (dart.library.io) 'web_clipboard_drag_io.dart';

class WebClipboardDrag {
  /// Initializes clipboard paste (Ctrl+V or Right-Click -> Paste) and drag-and-drop listeners on web.
  /// Only processes incoming events when [isActive] returns true (e.g. when Manual & Scan tab is visible).
  static void initListeners({
    required void Function(Uint8List bytes, String name) onImageReceived,
    required bool Function() isActive,
  }) {
    WebClipboardDragService.initListeners(
      onImageReceived: onImageReceived,
      isActive: isActive,
    );
  }

  /// Cleans up listeners to prevent memory leaks.
  static void disposeListeners() {
    WebClipboardDragService.disposeListeners();
  }

  /// Attempts to read image directly from clipboard if supported.
  static Future<Uint8List?> readImageFromClipboard() {
    return WebClipboardDragService.readImageFromClipboard();
  }
}
