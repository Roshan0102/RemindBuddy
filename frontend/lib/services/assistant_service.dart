import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../screens/voice_assistant_screen.dart';
import '../screens/add_task_screen.dart';
import '../screens/gym_active_workout_screen.dart';
import 'gold_price_service.dart';

/// Service handling incoming Google Assistant App Actions & launcher shortcuts.
/// Bridges OS voice queries seamlessly to SmartBuddy features with strict privacy guardrails.
class AssistantService {
  static final AssistantService _instance = AssistantService._internal();
  factory AssistantService() => _instance;
  AssistantService._internal();

  static const MethodChannel _channel = MethodChannel('com.remindbuddy/assistant_channel');
  static const EventChannel _stream = EventChannel('com.remindbuddy/assistant_stream');

  final FlutterTts _tts = FlutterTts();
  StreamSubscription? _streamSub;
  bool _isInitialized = false;

  void initialize(
    BuildContext context, {
    required Function(String feature) onNavigateToFeature,
  }) {
    if (kIsWeb) return;
    if (_isInitialized) return;
    _isInitialized = true;

    _initTts();

    // Check for initial intent that launched the app
    _channel.invokeMethod<Map<dynamic, dynamic>>('getInitialAssistantIntent').then((data) {
      if (data != null) {
        final map = Map<String, dynamic>.from(data);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          handleAssistantPayload(context, map, onNavigateToFeature: onNavigateToFeature);
        });
      }
    }).catchError((e) {
      debugPrint('[AssistantService] Error fetching initial intent: $e');
    });

    // Listen for live Assistant intents while running
    _streamSub?.cancel();
    _streamSub = _stream.receiveBroadcastStream().listen((dynamic event) {
      if (event is Map) {
        final map = Map<String, dynamic>.from(event);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          handleAssistantPayload(context, map, onNavigateToFeature: onNavigateToFeature);
        });
      }
    }, onError: (e) {
      debugPrint('[AssistantService] Stream error: $e');
    });
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
    } catch (e) {
      debugPrint('[AssistantService] TTS Init Error: $e');
    }
  }

  void handleUri(
    BuildContext context,
    Uri uri, {
    required Function(String feature) onNavigateToFeature,
  }) {
    final feature = uri.queryParameters['feature'] ??
        (uri.host == 'feature' && uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
    final action = uri.queryParameters['action'] ?? '';
    final query = uri.queryParameters['query'] ?? uri.queryParameters['q'] ?? '';

    handleAssistantPayload(
      context,
      {
        'feature': feature,
        'action': action,
        'query': query,
        'uri': uri.toString(),
      },
      onNavigateToFeature: onNavigateToFeature,
    );
  }

  Future<void> handleAssistantPayload(
    BuildContext context,
    Map<String, dynamic> data, {
    required Function(String feature) onNavigateToFeature,
  }) async {
    final feature = (data['feature'] ?? '').toString().trim().toLowerCase();
    final action = (data['action'] ?? '').toString().trim().toLowerCase();
    final query = (data['query'] ?? '').toString().trim();

    debugPrint('[AssistantService] Handling Assistant action: feature=$feature, action=$action, query=$query');

    // 1. STRICT PRIVACY GUARDRAIL: Reject any voice assistant intent for Vault or Finances
    if (isRestrictedFeature(feature)) {
      debugPrint('[AssistantService] Blocked attempt to access restricted module via voice.');
      await _speakSecurityWarning();
      return;
    }

    // 2. Query Handling (Custom voice query from "Hey Google, ask SmartBuddy...")
    if (query.isNotEmpty) {
      final queryLower = query.toLowerCase();

      // Check if query is trying to ask about Vault or Finance
      if (isRestrictedQuery(query)) {
        await _speakSecurityWarning();
        return;
      }

      // Check if query is asking for Gold Rate
      if (queryLower.contains('gold') &&
          (queryLower.contains('rate') ||
              queryLower.contains('price') ||
              queryLower.contains('cost') ||
              queryLower.contains('today'))) {
        onNavigateToFeature('gold');
        await _speakLiveGoldPrice();
        return;
      }

      // Route all other questions to SmartBuddy Voice AI Screen with query
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VoiceAssistantScreen(initialQuery: query),
        ),
      );
      return;
    }

    // 3. Feature-specific navigation
    switch (feature) {
      case 'gold':
        onNavigateToFeature('gold');
        await _speakLiveGoldPrice();
        break;

      case 'gym':
        if (action == 'start_workout') {
          onNavigateToFeature('gym');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const GymActiveWorkoutScreen(initialTitle: 'Quick Workout'),
            ),
          );
          await _tts.speak('Starting your gym workout session.');
        } else {
          onNavigateToFeature('gym');
          await _tts.speak('Opening gym tracker on SmartBuddy.');
        }
        break;

      case 'reminders':
      case 'tasks':
        if (action == 'create') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AddTaskScreen(),
            ),
          );
          await _tts.speak('Add your reminder on SmartBuddy.');
        } else {
          onNavigateToFeature('reminders');
          await _tts.speak('Opening reminders on SmartBuddy.');
        }
        break;

      case 'jobs':
      case 'job_assistant':
      case 'careers':
        onNavigateToFeature('job_assistant');
        await _tts.speak('Opening Job Assistant on SmartBuddy.');
        break;

      case 'notes':
        onNavigateToFeature('notes');
        await _tts.speak('Opening notes on SmartBuddy.');
        break;

      case 'shifts':
        onNavigateToFeature('shifts');
        await _tts.speak('Opening work shifts on SmartBuddy.');
        break;

      case 'voice_assistant':
      case 'assistant':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const VoiceAssistantScreen(),
          ),
        );
        break;

      default:
        debugPrint('[AssistantService] Unrecognized assistant feature: $feature');
        break;
    }
  }

  Future<void> _speakSecurityWarning() async {
    const warning =
        "For your privacy and security, Secure Vault and financial records cannot be accessed via voice commands. Please open the app and authenticate with your biometric fingerprint or PIN.";
    try {
      await _tts.speak(warning);
    } catch (_) {}
  }

  Future<void> _speakLiveGoldPrice() async {
    try {
      final res = await GoldPriceService().fetchCurrentGoldPrice();
      final priceObj = res['price'];
      if (priceObj != null && priceObj.price > 0) {
        final rate = priceObj.price.toInt();
        await _tts.speak("Today's 24 Karat gold rate in Chennai is ₹$rate per gram.");
      } else {
        await _tts.speak("Opening gold rates on SmartBuddy.");
      }
    } catch (e) {
      debugPrint('[AssistantService] Error reading gold price: $e');
      await _tts.speak("Opening gold rates on SmartBuddy.");
    }
  }

  /// Determines whether a requested feature is security-sensitive (Vault or Finances)
  /// and must be strictly forbidden via voice or external assistant triggers.
  static bool isRestrictedFeature(String feature) {
    final f = feature.toLowerCase().trim();
    return f == 'vault' ||
        f == 'secure_vault' ||
        f == 'finance' ||
        f == 'bank_accounts' ||
        f == 'expenses' ||
        f == 'debts' ||
        f == 'bills';
  }

  /// Determines whether a voice query contains sensitive keywords relating to
  /// Vault or Finances that must be blocked by the assistant security guardrail.
  static bool isRestrictedQuery(String query) {
    final q = query.toLowerCase();
    return q.contains('vault') ||
        q.contains('password') ||
        q.contains('secret') ||
        q.contains('credential') ||
        q.contains('bank') ||
        q.contains('balance') ||
        q.contains('expense') ||
        q.contains('transaction');
  }

  void dispose() {
    _streamSub?.cancel();
    _isInitialized = false;
  }
}
