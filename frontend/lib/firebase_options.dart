// File generated to support cross-platform Firebase config.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCbEjEIltmuR_SNUqJTbvzeiqm_XotIk0s',
    appId: '1:668661278882:web:8a30741a2cc173fcb30ffb',
    messagingSenderId: '668661278882',
    projectId: 'remindbuddy-b68f9',
    authDomain: 'remindbuddy-b68f9.firebaseapp.com',
    storageBucket: 'remindbuddy-b68f9.firebasestorage.app',
    measurementId: 'G-V12R3CLTW1',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCrq1DTxsaIg0S4MM7bOpjmZgX8-h97Dw4',
    appId: '1:668661278882:android:70a0bee09fe313fcb30ffb',
    messagingSenderId: '668661278882',
    projectId: 'remindbuddy-b68f9',
    storageBucket: 'remindbuddy-b68f9.firebasestorage.app',
  );
}
