// ignore_for_file: implementation_imports
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:file_picker/src/platform/web/file_picker_web.dart';
import 'package:image_picker_for_web/image_picker_for_web.dart';
import 'package:cloud_functions_web/cloud_functions_web.dart';
import 'package:firebase_storage_web/firebase_storage_web.dart';

void initWebPlugins() {
  try {
    FirebaseFunctionsWeb.registerWith(webPluginRegistrar);
  } catch (_) {}
  try {
    FirebaseStorageWeb.registerWith(webPluginRegistrar);
  } catch (_) {}
  try {
    FilePickerWeb.registerWith(webPluginRegistrar);
  } catch (_) {}
  try {
    ImagePickerPlugin.registerWith(webPluginRegistrar);
  } catch (_) {}
}
