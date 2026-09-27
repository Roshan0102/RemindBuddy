import 'url_launcher_helper_stub.dart'
    if (dart.library.html) 'url_launcher_helper_web.dart' as impl;

class UrlLauncherHelper {
  /// Opens a URL in a new browser tab on Web (safely bypassing browser popup blockers)
  /// or directly in external application (e.g. LinkedIn app) on Mobile.
  static Future<void> openInNewTabOrExternal(String url) async {
    await impl.openExternalUrl(url);
  }

  /// Triggers a native browser file download on Web with a specific filename
  static void downloadBase64(String cleanBase64, String filename, {String mimeType = 'application/pdf'}) {
    impl.downloadBase64File(cleanBase64, filename, mimeType);
  }
}
