// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'app_file_picker.dart';

class AppFilePickerImpl {
  static Future<AppPickedFile?> pickImage({bool fromCamera = false}) async {
    final list = await _pickWebFiles(
      accept: 'image/*',
      allowMultiple: false,
      fromCamera: fromCamera,
    );
    return list.isNotEmpty ? list.first : null;
  }

  static Future<List<AppPickedFile>> pickMultipleImages() async {
    return await _pickWebFiles(
      accept: 'image/*',
      allowMultiple: true,
    );
  }

  static Future<AppPickedFile?> pickPdf() async {
    final list = await _pickWebFiles(
      accept: '.pdf,application/pdf',
      allowMultiple: false,
    );
    return list.isNotEmpty ? list.first : null;
  }

  static Future<List<AppPickedFile>> pickFiles({
    List<String>? allowedExtensions,
    bool allowMultiple = true,
  }) async {
    String accept = '*/*';
    if (allowedExtensions != null && allowedExtensions.isNotEmpty) {
      accept = allowedExtensions
          .map((ext) => ext.startsWith('.') ? ext : '.$ext')
          .join(',');
    }
    return await _pickWebFiles(
      accept: accept,
      allowMultiple: allowMultiple,
    );
  }

  static Future<List<AppPickedFile>> _pickWebFiles({
    required String accept,
    required bool allowMultiple,
    bool fromCamera = false,
  }) {
    final completer = Completer<List<AppPickedFile>>();
    final input = html.FileUploadInputElement();
    input.accept = accept;
    input.multiple = allowMultiple;
    if (fromCamera) {
      input.setAttribute('capture', 'environment');
    }
    input.style.display = 'none';
    html.document.body?.children.add(input);

    bool completed = false;
    void finish(List<AppPickedFile> results) {
      if (!completed) {
        completed = true;
        try {
          input.remove();
        } catch (_) {}
        if (!completer.isCompleted) {
          completer.complete(results);
        }
      }
    }

    input.onChange.listen((event) {
      final files = input.files;
      if (files == null || files.isEmpty) {
        finish([]);
        return;
      }

      final results = <AppPickedFile>[];
      int processed = 0;

      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final reader = html.FileReader();
        reader.onLoadEnd.listen((_) {
          final res = reader.result;
          Uint8List? bytes;
          if (res is Uint8List) {
            bytes = res;
          } else if (res is ByteBuffer) {
            bytes = Uint8List.view(res);
          } else if (res is List<int>) {
            bytes = Uint8List.fromList(res);
          }
          if (bytes != null) {
            results.add(AppPickedFile(
              name: file.name,
              bytes: bytes,
              size: file.size,
            ));
          }
          processed++;
          if (processed == files.length) {
            finish(results);
          }
        });
        reader.onError.listen((_) {
          processed++;
          if (processed == files.length) {
            finish(results);
          }
        });
        reader.readAsArrayBuffer(file);
      }
    });

    // Native cancel event
    input.addEventListener('cancel', (e) {
      finish([]);
    });

    // Fallback: window focus detection if user dismisses file manager dialog
    void focusListener(html.Event e) {
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (!completed) {
          if (input.files == null || input.files!.isEmpty) {
            finish([]);
          }
        }
      });
    }

    html.window.addEventListener('focus', focusListener, false);

    completer.future.whenComplete(() {
      try {
        html.window.removeEventListener('focus', focusListener, false);
        input.remove();
      } catch (_) {}
    });

    // Programmatically open native file picker dialog
    input.click();

    return completer.future;
  }
}
