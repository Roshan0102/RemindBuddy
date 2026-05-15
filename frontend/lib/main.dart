import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/main_screen.dart';
import 'services/notification_service.dart';
import 'services/voice_assistant_service.dart';
import 'package:quick_settings/quick_settings.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Special entry point for the Floating Overlay
@pragma("vm:entry-point")
void overlayMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  // IMPORTANT: Re-initialize Firebase for this separate isolate
  await Firebase.initializeApp();
  
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: FloatingVoiceOverlay(),
  ));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    print("Error loading .env file: $e");
  }
  
  await initializeDateFormatting();
  
  // Initialize Voice Assistant
  final geminiKey = dotenv.env['GEMINI_API_KEY'] ?? "";
  if (geminiKey.isNotEmpty) {
    await VoiceAssistantService().init(geminiKey: geminiKey);
  }

  // Set up Quick Settings Tile
  QuickSettings.setup(
    onTap: () async {
      bool? status = await FlutterOverlayWindow.isPermissionGranted();
      if (!(status ?? false)) {
        await FlutterOverlayWindow.requestPermission();
        return;
      }

      final micStatus = await Permission.microphone.request();
      if (micStatus.isGranted) {
        if (!await FlutterOverlayWindow.isActive()) {
          await FlutterOverlayWindow.showOverlay(
            enableDrag: true,
            overlayTitle: "Buddy is listening",
            alignment: OverlayAlignment.bottomCenter,
            visibility: NotificationVisibility.visibilityPublic,
            height: 400,
            width: WindowSize.matchParent,
          );
        }
      }
    },
  );

  try {
    await NotificationService().init();
  } catch (e) {
    print('Error initializing services: $e');
  }
  
  runApp(const RemindBuddyApp());
}

class FloatingVoiceOverlay extends StatefulWidget {
  const FloatingVoiceOverlay({super.key});
  @override
  State<FloatingVoiceOverlay> createState() => _FloatingVoiceOverlayState();
}

class _FloatingVoiceOverlayState extends State<FloatingVoiceOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _status = "Listening...";

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _listen();
  }

  Future<void> _listen() async {
    try {
      await dotenv.load(fileName: ".env");
      await VoiceAssistantService().init(geminiKey: dotenv.env['GEMINI_API_KEY'] ?? "");
      
      await VoiceAssistantService().startListening(onResult: (text) {
        if (mounted) setState(() => _status = text);
      });
    } catch (e) {
      if (mounted) setState(() => _status = "Error: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.3), blurRadius: 10, spreadRadius: 2)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            ScaleTransition(
              scale: Tween(begin: 1.0, end: 1.2).animate(_controller),
              child: const Icon(Icons.mic, color: Colors.blueAccent, size: 45),
            ),
            const SizedBox(height: 15),
            Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => FlutterOverlayWindow.closeOverlay(),
              child: const Text("CLOSE BUDDY", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class RemindBuddyApp extends StatelessWidget {
  const RemindBuddyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RemindBuddy',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const MainScreen(),
    );
  }
}
