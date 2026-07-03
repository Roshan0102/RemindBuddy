import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_functions/cloud_functions.dart';

class VoiceAssistantScreen extends StatefulWidget {
  const VoiceAssistantScreen({super.key});

  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> with TickerProviderStateMixin {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _speechEnabled = false;
  bool _isListening = false;
  bool _isThinking = false;
  bool _isSpeaking = false;
  bool _textMode = false;
  bool _isMuted = false;
  String _currentTranscribedText = "";
  
  final List<Map<String, String>> _messages = [
    {
      "sender": "assistant",
      "text": "Hello! I am RemindBuddy. How can I help you today? You can ask me about your schedule, gold rates, notes, or checklists, or create reminders!"
    }
  ];

  late AnimationController _pulseController;
  late AnimationController _speakingWaveController;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initTts();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _speakingWaveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _speechToText.stop();
    _flutterTts.stop();
    _textController.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    _speakingWaveController.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onError: (errorNotification) {
          debugPrint("STT Error: ${errorNotification.errorMsg}");
          setState(() {
            _isListening = false;
            _pulseController.stop();
          });
          _showErrorSnackBar("Speech recognition error: ${errorNotification.errorMsg}");
        },
        onStatus: (status) {
          debugPrint("STT Status: $status");
          if (status == "notListening" || status == "done") {
            setState(() {
              _isListening = false;
              _pulseController.stop();
            });
          }
        },
      );
      setState(() {});
    } catch (e) {
      debugPrint("STT Init Exception: $e");
    }
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.0);
    
    _flutterTts.setStartHandler(() {
      setState(() {
        _isSpeaking = true;
        _speakingWaveController.repeat();
      });
    });

    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
        _speakingWaveController.stop();
      });
    });

    _flutterTts.setCancelHandler(() {
      setState(() {
        _isSpeaking = false;
        _speakingWaveController.stop();
      });
    });

    _flutterTts.setErrorHandler((msg) {
      debugPrint("TTS Error: $msg");
      setState(() {
        _isSpeaking = false;
        _speakingWaveController.stop();
      });
    });
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Future<void> _startListening() async {
    await _flutterTts.stop();
    setState(() {
      _isSpeaking = false;
      _speakingWaveController.stop();
    });

    if (!_speechEnabled) {
      await _initSpeech();
    }

    if (_speechEnabled) {
      setState(() {
        _isListening = true;
        _currentTranscribedText = "";
      });
      _pulseController.repeat();

      await _speechToText.listen(
        onResult: (result) {
          setState(() {
            _currentTranscribedText = result.recognizedWords;
          });
          if (result.finalResult) {
            _stopListeningAndSend(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 4),
        cancelOnError: true,
      );
    } else {
      _showErrorSnackBar("Microphone access or Speech recognition not available.");
    }
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
    setState(() {
      _isListening = false;
      _pulseController.stop();
    });
  }

  void _stopListeningAndSend(String words) {
    _stopListening();
    if (words.trim().isNotEmpty) {
      _sendMessage(words);
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add({"sender": "user", "text": text});
      _isThinking = true;
      _currentTranscribedText = "";
    });
    _scrollToBottom();

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('voiceAssistantQuery');
      final response = await callable.call({'query': text});
      
      final data = response.data;
      if (data != null && data['success'] == true) {
        final spokenResponse = data['spokenResponse'] as String? ?? "Sorry, I encountered an issue processing that.";
        
        setState(() {
          _messages.add({"sender": "assistant", "text": spokenResponse});
          _isThinking = false;
        });
        _scrollToBottom();

        // Speak response out loud if not muted
        if (!_isMuted) {
          await _flutterTts.speak(spokenResponse);
        }
      } else {
        throw Exception(data?['error'] ?? "Unknown function error");
      }
    } catch (e) {
      debugPrint("Voice assistant query error: $e");
      setState(() {
        _isThinking = false;
        _messages.add({
          "sender": "assistant",
          "text": "Sorry, I had trouble communicating with the server. Please check your network and try again."
        });
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF0F0C1B), const Color(0xFF201A30)]
                : [const Color(0xFFECE9E6), const Color(0xFFFFFFFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      "RemindBuddy Voice AI",
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              // Chat History
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0),
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(24.0),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg["sender"] == "user";
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6.0),
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                          decoration: BoxDecoration(
                            color: isUser
                                ? (isDark ? Colors.cyan.shade900 : Colors.indigo)
                                : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16.0),
                              topRight: const Radius.circular(16.0),
                              bottomLeft: isUser ? const Radius.circular(16.0) : const Radius.circular(4.0),
                              bottomRight: isUser ? const Radius.circular(4.0) : const Radius.circular(16.0),
                            ),
                          ),
                          child: Text(
                            msg["text"] ?? "",
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              color: isUser
                                  ? Colors.white
                                  : (isDark ? const Color(0xFFEFEFEF) : Colors.black87),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16.0),

              // Live transcribing banner / status
              if (_currentTranscribedText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    _currentTranscribedText,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.cyanAccent : Colors.indigo,
                    ),
                  ),
                )
              else if (_isThinking)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyan),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Thinking...",
                      style: GoogleFonts.outfit(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  ],
                )
              else if (_isSpeaking)
                Text(
                  "Speaking...",
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.pinkAccent : Colors.deepOrange,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),

              const SizedBox(height: 16.0),

              // Interactive Assistant Area
              Padding(
                padding: const EdgeInsets.fromLTRB(20.0, 8.0, 20.0, 24.0),
                child: _textMode
                    ? Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.mic, color: Colors.grey),
                            onPressed: () {
                              setState(() {
                                _textMode = false;
                              });
                            },
                          ),
                          Expanded(
                            child: TextField(
                              controller: _textController,
                              style: GoogleFonts.outfit(color: isDark ? Colors.white : Colors.black87),
                              decoration: InputDecoration(
                                hintText: "Ask RemindBuddy...",
                                hintStyle: GoogleFonts.outfit(color: Colors.grey),
                                filled: true,
                                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(30.0),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                              ),
                              onSubmitted: (val) {
                                if (val.trim().isNotEmpty) {
                                  _sendMessage(val);
                                  _textController.clear();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          IconButton(
                            style: IconButton.styleFrom(
                              backgroundColor: isDark ? Colors.cyan.shade900 : Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(12.0),
                            ),
                            icon: const Icon(Icons.send),
                            onPressed: () {
                              final text = _textController.text;
                              if (text.trim().isNotEmpty) {
                                _sendMessage(text);
                                _textController.clear();
                              }
                            },
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            style: IconButton.styleFrom(
                              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                              padding: const EdgeInsets.all(16.0),
                            ),
                            icon: Icon(Icons.keyboard, size: 28, color: isDark ? Colors.white70 : Colors.black54),
                            onPressed: () {
                              setState(() {
                                _textMode = true;
                              });
                            },
                          ),
                          GestureDetector(
                            onTap: () {
                              if (_isListening) {
                                _stopListeningAndSend(_currentTranscribedText);
                              } else {
                                _startListening();
                              }
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (_isListening)
                                  AnimatedBuilder(
                                    animation: _pulseController,
                                    builder: (context, child) {
                                      return Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          _buildPulseRing(1.0 + _pulseController.value * 0.8, (1.0 - _pulseController.value) * 0.4, isDark),
                                          _buildPulseRing(1.0 + ((_pulseController.value + 0.5) % 1.0) * 0.8, (1.0 - ((_pulseController.value + 0.5) % 1.0)) * 0.4, isDark),
                                        ],
                                      );
                                    },
                                  ),
                                if (_isSpeaking)
                                  AnimatedBuilder(
                                    animation: _speakingWaveController,
                                    builder: (context, child) {
                                      final scaleVal = 1.0 + (_speakingWaveController.value * 0.3);
                                      return Container(
                                        width: 130 * scaleVal,
                                        height: 130 * scaleVal,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.pink.withValues(alpha: 0.05 + (1.0 - _speakingWaveController.value) * 0.1),
                                          border: Border.all(
                                            color: Colors.pinkAccent.withValues(alpha: 0.15 + (1.0 - _speakingWaveController.value) * 0.3),
                                            width: 2,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: _isListening
                                          ? [Colors.cyan.shade400, Colors.blue.shade900]
                                          : (_isSpeaking
                                              ? [Colors.pink.shade400, Colors.deepOrange]
                                              : [const Color(0xFF8E2DE2), const Color(0xFF4A00E0)]),
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (_isListening
                                            ? Colors.cyanAccent
                                            : (_isSpeaking ? Colors.pinkAccent : const Color(0xFF8E2DE2)))
                                            .withValues(alpha: 0.4),
                                        blurRadius: 15,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    _isListening ? Icons.mic : (_isSpeaking ? Icons.volume_up : Icons.mic_none),
                                    size: 38,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            style: IconButton.styleFrom(
                              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                              padding: const EdgeInsets.all(16.0),
                            ),
                            icon: Icon(
                              _isMuted ? Icons.volume_off : Icons.volume_up,
                              size: 28,
                              color: _isMuted 
                                  ? Colors.redAccent 
                                  : (isDark ? Colors.white70 : Colors.black54),
                            ),
                            onPressed: () {
                              setState(() {
                                _isMuted = !_isMuted;
                                if (_isMuted) {
                                  _flutterTts.stop();
                                }
                              });
                            },
                          ),
                        ],
                      ),
              ),

              // Footer helper hint
              if (!_textMode)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: Text(
                    _isListening 
                        ? "Tap microphone to finish speaking" 
                        : (_isSpeaking ? "Tap microphone to stop speech" : "Tap microphone to talk to RemindBuddy"),
                    style: GoogleFonts.outfit(
                      color: Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPulseRing(double scale, double opacity, bool isDark) {
    final ringColor = isDark ? Colors.cyanAccent : Colors.indigoAccent;
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ringColor, width: 3),
            boxShadow: [
              BoxShadow(
                color: ringColor.withValues(alpha: 0.2),
                blurRadius: 15,
                spreadRadius: 5,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Add simple Colors helper
extension ColorsExt on Colors {
  static const Color whiteEF = Color(0xFFEFEFEF);
}
