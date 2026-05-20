import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:async';
import 'gold_price_service.dart';
import 'storage_service.dart';
import '../models/shift.dart';
import '../models/note.dart';

class VoiceAssistantService {
  static final VoiceAssistantService _instance = VoiceAssistantService._internal();
  factory VoiceAssistantService() => _instance;
  VoiceAssistantService._internal();

  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  GenerativeModel? _model;
  
  bool _isSpeechInitialized = false;
  bool _isListening = false;
  bool _isInitialized = false;

  final StreamController<String> _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  // Logging fields
  String? _currentSessionId;
  List<Map<String, dynamic>> _sessionEvents = [];
  DateTime? _sessionStartTime;
  Timer? _silenceTimer;

  void updateStatus(String status) {
    _statusController.add(status);
  }

  Future<void> startSession() async {
    final user = FirebaseAuth.instance.currentUser;
    _currentSessionId = "session_${DateTime.now().millisecondsSinceEpoch}_${user?.uid ?? 'anon'}";
    _sessionStartTime = DateTime.now();
    _sessionEvents = [];
    
    await logEvent("Session Started", details: "User opened the voice assistant screen.");
  }

  Future<void> logEvent(String type, {String? details}) async {
    if (_currentSessionId == null) return;
    
    final event = {
      "timestamp": DateTime.now().toIso8601String(),
      "type": type,
      "details": details ?? "",
    };
    _sessionEvents.add(event);
    
    final user = FirebaseAuth.instance.currentUser;
    try {
      await FirebaseFirestore.instance
          .collection('voice_assistant_logs')
          .doc(_currentSessionId)
          .set({
        "sessionId": _currentSessionId,
        "userId": user?.uid ?? "anonymous",
        "userEmail": user?.email ?? "anonymous",
        "startTimestamp": _sessionStartTime?.toIso8601String(),
        "endTimestamp": null,
        "events": _sessionEvents,
      }, SetOptions(merge: true));
    } catch (e) {
      print("Error writing log to Firestore: $e");
    }
  }

  Future<void> endSession() async {
    if (_currentSessionId == null) return;
    
    _silenceTimer?.cancel();
    await logEvent("Session Ended", details: "User closed the voice assistant screen.");
    
    try {
      await FirebaseFirestore.instance
          .collection('voice_assistant_logs')
          .doc(_currentSessionId)
          .update({
        "endTimestamp": DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print("Error updating endTimestamp: $e");
    }
    _currentSessionId = null;
  }

  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    try {
      await dotenv.load(fileName: ".env");
      final geminiKey = dotenv.env['GEMINI_API_KEY'] ?? "";
      _model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: geminiKey,
      );
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      _isInitialized = true;
      await logEvent("Service Initialized", details: "Gemini and TTS engines initialized successfully.");
    } catch (e) {
      print("Lazy initialization error: $e");
      await logEvent("Initialization Failed", details: e.toString());
    }
  }

  Future<void> startListening({Function(String)? onResult}) async {
    await _ensureInitialized();
    if (_isListening) return;
    
    await logEvent("Listening Attempt", details: "Requesting SpeechToText initialize...");
    updateStatus("Initializing microphone...");
    
    _isSpeechInitialized = await _speechToText.initialize(
      onError: (errorNotification) {
        print("🎙️ SpeechToText Error: ${errorNotification.errorMsg}");
        updateStatus("Speech Error: ${errorNotification.errorMsg}. Try typing below!");
        logEvent("Speech Error", details: errorNotification.errorMsg);
        _isListening = false;
      },
      onStatus: (status) {
        print("🎙️ SpeechToText Status: $status");
        if (status == "listening") {
          updateStatus("Listening... speak now!");
          logEvent("Listening Status", details: "Microphone is listening.");
        } else if (status == "notListening") {
          updateStatus("Stopped listening. Processing...");
          logEvent("Listening Status", details: "Microphone stopped listening.");
        }
      },
    );
    
    if (_isSpeechInitialized) {
      _isListening = true;
      _speechToText.listen(
        onResult: (result) {
          if (result.recognizedWords.isNotEmpty) {
            updateStatus("You said: ${result.recognizedWords}");
            logEvent("Live Transcription", details: result.recognizedWords);
          }
          
          // Reset silence timer on every recognized word chunk (1.5s timeout)
          _silenceTimer?.cancel();
          _silenceTimer = Timer(const Duration(milliseconds: 1500), () {
            if (_speechToText.isListening) {
              _speechToText.stop();
              _isListening = false;
              if (onResult != null) onResult(result.recognizedWords);
              logEvent("Speech Finished", details: "Auto-stopped due to silence. Word: ${result.recognizedWords}");
              processCommand(result.recognizedWords);
            }
          });
          
          if (result.finalResult) {
            _silenceTimer?.cancel();
            _isListening = false;
            if (onResult != null) onResult(result.recognizedWords);
            logEvent("Speech Finished", details: "FinalResult recognized. Word: ${result.recognizedWords}");
            processCommand(result.recognizedWords);
          }
        },
      );
    } else {
      updateStatus("Failed to initialize microphone. You can type your request below!");
      await logEvent("Listening Failed", details: "Microphone failed to initialize.");
    }
  }

  Future<void> stopListening() async {
    _silenceTimer?.cancel();
    await _speechToText.stop();
    _isListening = false;
    await logEvent("Listening Stopped", details: "Microphone was manually stopped.");
  }

  Future<void> processCommand(String command) async {
    await _ensureInitialized();
    updateStatus("Thinking...");
    await logEvent("Command Input", details: command);

    if (_model == null) {
      final msg = "Gemini API key is not configured. Please add it to your .env file.";
      updateStatus("Buddy: $msg");
      await logEvent("Process Failed", details: "Gemini model was null/uninitialized.");
      await speak(msg);
      return;
    }

    print("🎙️ Processing command: $command");
    await logEvent("Fetching Context", details: "Gathering Firestore records for the user...");

    final context = await _getAssistantContext();
    await logEvent("Context Retrieved", details: context);

    final prompt = """
    You are 'Buddy', the official AI assistant for the RemindBuddy app. 
    The user is asking: "$command"
    
    Here is the REAL-TIME DATA from the user's app database:
    $context
    
    INSTRUCTIONS:
    1. Answer based ONLY on the provided context if the user asks about their data (shifts, gold, notes, checklists).
    2. If they ask about a checklist (e.g., 'office checklist'), list the items found in the context.
    3. If they ask about notes, summarize or read them.
    4. Keep your answers natural, friendly, and brief (max 3-4 sentences).
    """;

    try {
      await logEvent("Gemini Request Sent", details: prompt);
      final content = [Content.text(prompt)];
      final response = await _model!.generateContent(content);
      final reply = response.text ?? "I'm sorry, I couldn't find that in your data.";
      
      print("🤖 Assistant: $reply");
      updateStatus("Buddy: $reply");
      await logEvent("Gemini Response Received", details: reply);
      await speak(reply);
    } catch (e) {
      print("❌ Gemini Error: $e");
      final errorMsg = "Sorry, I'm having trouble reading your data right now.";
      updateStatus("Buddy: $errorMsg");
      await logEvent("Gemini API Error", details: e.toString());
      await speak(errorMsg);
    }
  }

  Future<String> _getAssistantContext() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return "User is not logged in. No data available.";

    String context = "--- USER DATA ---\n";
    
    // 1. Gold Price
    try {
      final goldData = await GoldPriceService().fetchCurrentGoldPrice();
      if (goldData['price'] != null) {
        context += "GOLD: Current price is ${goldData['price'].price} per ${goldData['price'].unit}.\n";
      }
    } catch (e) {
      await logEvent("Context Error (Gold)", details: e.toString());
    }

    // 2. Tomorrow's Shift
    try {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final tomorrowStr = "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";
      final shiftData = await StorageService().getShiftForDate(tomorrowStr);
      if (shiftData != null) {
        final shift = Shift.fromMap(shiftData);
        context += "SHIFT: Tomorrow (${tomorrowStr}) you have a ${shift.getDisplayName()} (${shift.getTimeRange()}).\n";
      } else {
        context += "SHIFT: No shift found for tomorrow.\n";
      }
    } catch (e) {
      await logEvent("Context Error (Shifts)", details: e.toString());
    }

    // 3. Notes
    try {
      final notes = await StorageService().getNotes();
      if (notes.isNotEmpty) {
        context += "NOTES:\n";
        for (var note in notes.take(5)) {
          context += "- Title: ${note.title}, Content: ${note.content}\n";
        }
      }
    } catch (e) {
      await logEvent("Context Error (Notes)", details: e.toString());
    }

    // 4. Checklists
    try {
      final checklists = await StorageService().getChecklists();
      if (checklists.isNotEmpty) {
        context += "CHECKLISTS:\n";
        for (var list in checklists) {
          context += "List Name: ${list['title']}\n";
          // Fetch items for this list
          final itemsSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('checklists')
              .doc(list['id'])
              .collection('items')
              .get();
          for (var item in itemsSnap.docs) {
            final data = item.data();
            context += "  - Item: ${data['text']} (Status: ${data['isChecked'] ? 'Checked' : 'Unchecked'})\n";
          }
        }
      }
    } catch (e) {
      await logEvent("Context Error (Checklists)", details: e.toString());
    }

    return context;
  }

  Future<void> speak(String text) async {
    await logEvent("Speech Started", details: text);
    await _flutterTts.speak(text);
  }
}
