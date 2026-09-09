import 'url_launcher_helper_stub.dart'
    if (dart.library.html) 'url_launcher_helper_web.dart' as impl;

class UrlLauncherHelper {
  /// Opens a URL in a new browser tab on Web (safely bypassing browser popup blockers)
  /// or directly in external application (e.g. LinkedIn app) on Mobile.
  static Future<void> openInNewTabOrExternal(String url) async {
    await impl.openExternalUrl(url);
  }
}
