// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class WebClipboardDragService {
  static StreamSubscription<html.ClipboardEvent>? _pasteSub;
  static StreamSubscription<html.MouseEvent>? _dragOverSub;
  static StreamSubscription<html.MouseEvent>? _dropSub;

  static void initListeners({
    required void Function(Uint8List bytes, String name) onImageReceived,
    required bool Function() isActive,
  }) {
    disposeListeners();

    // 1. Listen for global Paste (Ctrl+V or Right-Click -> Paste)
    _pasteSub = html.document.onPaste.listen((html.ClipboardEvent event) {
      if (!isActive()) return;

      final items = event.clipboardData?.items;
      if (items == null) return;

      final count = items.length ?? 0;
      for (int i = 0; i < count; i++) {
        final item = items[i];
        if (item.type != null && item.type!.startsWith('image/')) {
          final file = item.getAsFile();
          if (file != null) {
            _readFile(file, (bytes, name) {
              onImageReceived(bytes, name);
            });
            event.preventDefault();
            break;
          }
        }
      }
    });

    // 2. Prevent default browser file opening on Drag Over
    _dragOverSub = html.document.body?.onDragOver.listen((event) {
      if (isActive()) {
        event.preventDefault();
      }
    });

    // 3. Listen for File Drops (Drag and Drop from desktop / file manager / browser)
    _dropSub = html.document.body?.onDrop.listen((html.MouseEvent event) {
      if (!isActive()) return;

      final files = (event as dynamic).dataTransfer?.files;
      if (files != null && files.length > 0) {
        bool handled = false;
        for (int i = 0; i < files.length; i++) {
          final file = files[i];
          final type = file.type?.toLowerCase() ?? '';
          final name = file.name?.toLowerCase() ?? '';
          final isImage = type.startsWith('image/') ||
              name.endsWith('.png') ||
              name.endsWith('.jpg') ||
              name.endsWith('.jpeg') ||
              name.endsWith('.webp') ||
              name.endsWith('.bmp');

          if (isImage) {
            _readFile(file, (bytes, fileName) {
              onImageReceived(bytes, fileName);
            });
            handled = true;
          }
        }
        if (handled) {
          event.preventDefault();
        }
      }
    });
  }

  static void _readFile(dynamic file, void Function(Uint8List bytes, String name) onDone) {
    try {
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      reader.onLoadEnd.listen((_) {
        if (reader.result != null) {
          final bytes = Uint8List.fromList(reader.result as List<int>);
          final name = (file.name != null && file.name.toString().isNotEmpty)
              ? file.name.toString()
              : 'pasted_image_${DateTime.now().millisecondsSinceEpoch}.png';
          onDone(bytes, name);
        }
      });
    } catch (e) {
      // Fallback
    }
  }

  static void disposeListeners() {
    _pasteSub?.cancel();
    _pasteSub = null;
    _dragOverSub?.cancel();
    _dragOverSub = null;
    _dropSub?.cancel();
    _dropSub = null;
  }

  static Future<Uint8List?> readImageFromClipboard() async {
    // Note: Browser security policies generally require user gesture or native onPaste event
    return null;
  }
}
