import 'web_plugin_init_stub.dart'
    if (dart.library.html) 'web_plugin_init_web.dart';

void ensureWebPluginsInitialized() {
  initWebPlugins();
}
