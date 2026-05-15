import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  Future<void> init({required String geminiKey}) async {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: geminiKey,
    );
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
  }

  Future<void> startListening({Function(String)? onResult}) async {
    if (_isListening) return;
    _isSpeechInitialized = await _speechToText.initialize();
    if (_isSpeechInitialized) {
      _isListening = true;
      _speechToText.listen(
        onResult: (result) {
          if (result.finalResult) {
            _isListening = false;
            if (onResult != null) onResult(result.recognizedWords);
            processCommand(result.recognizedWords);
          }
        },
      );
    }
  }

  Future<void> stopListening() async {
    await _speechToText.stop();
    _isListening = false;
  }

  Future<void> processCommand(String command) async {
    if (_model == null) return;
    print("🎙️ Processing command: $command");

    final context = await _getAssistantContext();
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
      final content = [Content.text(prompt)];
      final response = await _model!.generateContent(content);
      final reply = response.text ?? "I'm sorry, I couldn't find that in your data.";
      print("🤖 Assistant: $reply");
      await speak(reply);
    } catch (e) {
      print("❌ Gemini Error: $e");
      await speak("Sorry, I'm having trouble reading your data right now.");
    }
  }

  Future<String> _getAssistantContext() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return "User is not logged in. No data available.";

    String context = "--- USER DATA ---\n";
    
    // 1. Gold Price
    final goldData = await GoldPriceService().fetchCurrentGoldPrice();
    if (goldData['price'] != null) {
      context += "GOLD: Current price is ${goldData['price'].price} per ${goldData['price'].unit}.\n";
    }

    // 2. Tomorrow's Shift
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final tomorrowStr = "${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";
    final shiftData = await StorageService().getShiftForDate(tomorrowStr);
    if (shiftData != null) {
      final shift = Shift.fromMap(shiftData);
      context += "SHIFT: Tomorrow (${tomorrowStr}) you have a ${shift.getDisplayName()} (${shift.getTimeRange()}).\n";
    } else {
      context += "SHIFT: No shift found for tomorrow.\n";
    }

    // 3. Notes
    final notes = await StorageService().getNotes();
    if (notes.isNotEmpty) {
      context += "NOTES:\n";
      for (var note in notes.take(5)) {
        context += "- Title: ${note.title}, Content: ${note.content}\n";
      }
    }

    // 4. Checklists
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

    return context;
  }

  Future<void> speak(String text) async {
    await _flutterTts.speak(text);
  }
}
