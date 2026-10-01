import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/app_permission_service.dart';

class InAppCallScreen extends StatefulWidget {
  final String sessionId;
  final String companyName;
  final String jobTitle;
  final String recruiterName;
  final String recruiterEmail;
  final String question;
  final String candidateName;
  final bool initialRinging;

  const InAppCallScreen({
    super.key,
    required this.sessionId,
    required this.companyName,
    required this.jobTitle,
    required this.recruiterName,
    this.recruiterEmail = '',
    required this.question,
    required this.candidateName,
    this.initialRinging = true,
  });

  @override
  State<InAppCallScreen> createState() => _InAppCallScreenState();
}

class _InAppCallScreenState extends State<InAppCallScreen> with TickerProviderStateMixin {
  static const Color emerald = Color(0xFF10B981);

  late bool _isRinging;
  bool _isCallActive = false;
  bool _isCallEnded = false;

  // Audio & Speech
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _speechEnabled = false;
  bool _isListening = false;
  bool _isAiSpeaking = false;
  bool _isProcessing = false;
  bool _isMuted = false;
  bool _isSpeakerOn = true;

  // Timer
  Timer? _callTimer;
  Timer? _silenceTimer;
  int _callSeconds = 0;

  // Transcripts & Chat
  final List<Map<String, String>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  String _currentSpokenText = '';
  String _statusMessage = 'Connecting...';

  // Animations
  late AnimationController _pulseController;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _isRinging = widget.initialRinging;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _initSpeechAndTts();

    if (!_isRinging) {
      _startActiveCall();
    }
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _silenceTimer?.cancel();
    _speechToText.stop();
    _flutterTts.stop();
    _pulseController.dispose();
    _waveController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initSpeechAndTts() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onError: (err) {
          debugPrint('[CallScreen] STT Error: ${err.errorMsg}');
          if (mounted && !_isAiSpeaking && !_isProcessing) {
            setState(() {
              _isListening = false;
              _waveController.stop();
            });
          }
        },
        onStatus: (status) {
          debugPrint('[CallScreen] STT Status: $status');
          if (status == 'done' || status == 'notListening') {
            if (mounted && _isListening && !_isAiSpeaking && !_isProcessing) {
              if (_currentSpokenText.trim().isEmpty) {
                // Keep listening active so the user can speak at their own pace
                Future.delayed(const Duration(milliseconds: 400), () {
                  if (mounted && _isListening && !_isAiSpeaking && !_isProcessing && !_isMuted) {
                    _startListening();
                  }
                });
              } else {
                // If user has spoken words, start a generous 2-second silence debounce timer
                _silenceTimer ??= Timer(const Duration(milliseconds: 2000), () {
                  if (mounted && _isListening && _currentSpokenText.trim().isNotEmpty && !_isAiSpeaking && !_isProcessing) {
                    _onUserFinishedSpeaking();
                  }
                });
              }
            }
          }
        },
      );
    } catch (e) {
      debugPrint('[CallScreen] STT Init failed: $e');
    }

    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.50);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.awaitSpeakCompletion(true);

      _flutterTts.setStartHandler(() {
        if (mounted) {
          setState(() {
            _isAiSpeaking = true;
            _waveController.repeat(reverse: true);
            _statusMessage = 'SmartBuddy is speaking...';
          });
        }
      });

      _flutterTts.setCompletionHandler(() {
        if (mounted) {
          setState(() {
            _isAiSpeaking = false;
            _waveController.stop();
            _statusMessage = 'Listening to you...';
          });
          if (!_isCallEnded && !_isMuted && !_isProcessing) {
            _startListening();
          }
        }
      });

      _flutterTts.setErrorHandler((msg) {
        debugPrint('[CallScreen] TTS Error: $msg');
        if (mounted) {
          setState(() {
            _isAiSpeaking = false;
            _waveController.stop();
            _statusMessage = 'Listening to you...';
          });
          if (!_isCallEnded && !_isMuted && !_isProcessing) {
            _startListening();
          }
        }
      });
    } catch (e) {
      debugPrint('[CallScreen] TTS Init failed: $e');
    }
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callSeconds++;
        });
      }
    });
  }

  String _formatCallDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _startActiveCall() async {
    setState(() {
      _isRinging = false;
      _isCallActive = true;
      _statusMessage = 'Call connected';
    });

    _startCallTimer();

    // Mark session in_call in Firestore
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && widget.sessionId.isNotEmpty) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('voice_call_sessions')
          .doc(widget.sessionId)
          .update({'status': 'in_call', 'callStartedAt': FieldValue.serverTimestamp()})
          .catchError((_) {});
    }

    // Opening greeting from SmartBuddy
    final greeting = "Hi ${widget.candidateName.split(' ').first}, "
        "${widget.recruiterName} from ${widget.companyName} replied to your application for ${widget.jobTitle}. "
        "They asked: '${widget.question}'. "
        "What would you like me to tell them?";

    setState(() {
      _messages.add({'role': 'assistant', 'text': greeting});
    });

    await Future.delayed(const Duration(milliseconds: 300));
    await _speakText(greeting);
  }

  Future<void> _speakText(String text) async {
    if (_isCallEnded) return;
    _silenceTimer?.cancel();
    try {
      await _speechToText.stop();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isListening = false;
        _isAiSpeaking = true;
        _waveController.repeat(reverse: true);
        _statusMessage = 'SmartBuddy is speaking...';
      });
    }

    try {
      await _flutterTts.awaitSpeakCompletion(true);
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('[CallScreen] TTS speak error: $e');
    } finally {
      if (mounted && !_isCallEnded && !_isMuted && !_isProcessing) {
        setState(() {
          _isAiSpeaking = false;
          _waveController.stop();
          _statusMessage = 'Listening to you...';
        });
        await Future.delayed(const Duration(milliseconds: 300));
        _startListening();
      }
    }
  }

  Future<void> _startListening() async {
    if (_isCallEnded || _isMuted || _isAiSpeaking || _isProcessing) return;

    final hasMic = await AppPermissionService().ensureMicrophonePermission(context);
    if (!hasMic || !_speechEnabled) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Microphone permission needed';
        });
      }
      return;
    }

    _silenceTimer?.cancel();
    _silenceTimer = null;

    if (mounted) {
      setState(() {
        _isListening = true;
        _statusMessage = 'Listening to you... Speak freely';
        _waveController.repeat(reverse: true);
      });
    }

    try {
      await _speechToText.listen(
        onResult: (result) {
          if (!mounted || _isAiSpeaking || _isProcessing) return;
          setState(() {
            _currentSpokenText = result.recognizedWords;
          });
          _scrollToBottom();

          // Reset silence timer on every recognized word chunk (2.4s debounce)
          _silenceTimer?.cancel();
          _silenceTimer = Timer(const Duration(milliseconds: 2400), () {
            if (mounted && _isListening && _currentSpokenText.trim().isNotEmpty && !_isAiSpeaking && !_isProcessing) {
              _onUserFinishedSpeaking();
            }
          });
        },
        listenOptions: SpeechListenOptions(
          cancelOnError: false,
          partialResults: true,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(seconds: 45),
          pauseFor: const Duration(seconds: 4),
          localeId: 'en_US',
        ),
      );
    } catch (e) {
      debugPrint('[CallScreen] STT listen exception: $e');
    }
  }

  Future<void> _onUserFinishedSpeaking() async {
    _silenceTimer?.cancel();
    _silenceTimer = null;

    if (_currentSpokenText.trim().isEmpty || _isCallEnded || _isAiSpeaking || _isProcessing) return;

    final userSpeech = _currentSpokenText.trim();
    _currentSpokenText = '';

    try {
      await _speechToText.stop();
    } catch (_) {}

    setState(() {
      _isListening = false;
      _messages.add({'role': 'user', 'text': userSpeech});
      _isProcessing = true;
      _statusMessage = 'Thinking with Groq AI...';
      _waveController.stop();
    });

    _scrollToBottom();

    try {
      // Call voiceCallChatTurn Cloud Function with full metadata
      final callable = FirebaseFunctions.instance.httpsCallable(
        'voiceCallChatTurn',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
      );

      final res = await callable.call({
        'sessionId': widget.sessionId,
        'userSpeech': userSpeech,
        'conversationHistory': _messages,
        'companyName': widget.companyName,
        'jobTitle': widget.jobTitle,
        'recruiterName': widget.recruiterName,
        'recruiterEmail': widget.recruiterEmail,
        'question': widget.question,
        'candidateName': widget.candidateName,
      });

      final data = Map<String, dynamic>.from(res.data ?? {});
      final replyText = data['replyText'] as String? ?? "I've noted that down. Should I send this reply?";
      final isConfirmed = data['isConfirmed'] as bool? ?? false;
      final engineUsed = data['engineUsed'] as String? ?? 'Groq';

      if (mounted) {
        setState(() {
          _messages.add({'role': 'assistant', 'text': replyText});
          _isProcessing = false;
          _statusMessage = 'Powered by $engineUsed';
        });
        _scrollToBottom();
      }

      await _speakText(replyText);

      // If user confirmed to send email, dispatch email and close call
      if (isConfirmed && !_isCallEnded) {
        _handleSendApprovedEmail(userSpeech);
      }
    } catch (e) {
      debugPrint('[CallScreen] Error in voice turn: $e');
      final fallbackReply = "Got it! Would you like me to send this reply to ${widget.recruiterName}?";
      if (mounted) {
        setState(() {
          _messages.add({'role': 'assistant', 'text': fallbackReply});
          _isProcessing = false;
          _statusMessage = 'SmartBuddy Assistant';
        });
        _scrollToBottom();
      }
      await _speakText(fallbackReply);
    }
  }

  Future<void> _handleSendApprovedEmail(String userConfirmedDetails) async {
    final userAnswers = _messages
        .where((m) => m['role'] == 'user')
        .map((m) => m['text'])
        .join(". ");

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('sendVoiceCallApprovedReply');
      await callable.call({
        'sessionId': widget.sessionId,
        'finalReplyText': userAnswers.isNotEmpty ? userAnswers : "Confirmed as discussed in the voice call.",
      });

      if (mounted) {
        setState(() {
          _statusMessage = 'Email successfully sent to recruiter! 🚀';
        });
      }

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _endCall(status: 'completed');
        }
      });
    } catch (e) {
      debugPrint('[CallScreen] Error sending approved email: $e');
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

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      if (_isMuted) {
        _speechToText.stop();
        _isListening = false;
        _waveController.stop();
        _statusMessage = 'Microphone Muted';
      } else {
        _startListening();
      }
    });
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
  }

  void _endCall({String status = 'completed'}) {
    setState(() {
      _isCallEnded = true;
      _isCallActive = false;
      _isRinging = false;
    });

    _callTimer?.cancel();
    _speechToText.stop();
    _flutterTts.stop();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && widget.sessionId.isNotEmpty) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('voice_call_sessions')
          .doc(widget.sessionId)
          .update({'status': status, 'callEndedAt': FieldValue.serverTimestamp()})
          .catchError((_) {});
    }

    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isCallActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isCallActive) {
          _endCall();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F19),
        body: SafeArea(
          child: _isRinging ? _buildRingingView() : _buildActiveCallView(),
        ),
      ),
    );
  }

  // --- 1. RINGING SCREEN (INCOMING CALL) ---
  Widget _buildRingingView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(height: 32),
        // Caller Info Header
        Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: emerald.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: emerald.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.phone_in_talk_rounded, color: emerald, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'INCOMING AI VOICE CALL',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: emerald,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.companyName,
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              widget.jobTitle,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade400,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Recruiter: ${widget.recruiterName}',
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: Colors.blueAccent.shade100,
              ),
            ),
          ],
        ),

        // Glowing Pulsing Avatar
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = 1.0 + (_pulseController.value * 0.12);
            return Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow
                Container(
                  width: 190 * scale,
                  height: 190 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: emerald.withValues(alpha: 0.08 * (1.0 - _pulseController.value)),
                  ),
                ),
                // Mid glow
                Container(
                  width: 150 * scale,
                  height: 150 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: emerald.withValues(alpha: 0.15),
                  ),
                ),
                // Core circle
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: emerald.withValues(alpha: 0.5),
                        blurRadius: 28,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      widget.companyName.isNotEmpty ? widget.companyName.substring(0, 1).toUpperCase() : 'J',
                      style: GoogleFonts.outfit(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),

        // Action Required Preview Card
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              const Icon(Icons.help_outline_rounded, color: Colors.amber, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Question Asked by Recruiter:',
                      style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.question,
                      style: GoogleFonts.outfit(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Accept / Decline Buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Decline Button
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => _endCall(status: 'declined'),
                    borderRadius: BorderRadius.circular(40),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Color(0x66EF4444), blurRadius: 18, spreadRadius: 2),
                        ],
                      ),
                      child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 34),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('Decline', style: GoogleFonts.outfit(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),

              // Accept Button
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: _startActiveCall,
                    borderRadius: BorderRadius.circular(40),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Color(0x6610B981), blurRadius: 18, spreadRadius: 2),
                        ],
                      ),
                      child: const Icon(Icons.call_rounded, color: Colors.white, size: 34),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('Accept', style: GoogleFonts.outfit(color: emerald, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- 2. ACTIVE CALL SCREEN (IN-CALL) ---
  Widget _buildActiveCallView() {
    return Column(
      children: [
        // Top Bar: Company info & Call timer
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.companyName,
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.jobTitle,
                      style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade400),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: emerald, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(
                      _formatCallDuration(_callSeconds),
                      style: GoogleFonts.robotoMono(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const Divider(color: Colors.white10, height: 1),

        // Live Audio Visualizer Animation
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              AnimatedBuilder(
                animation: _waveController,
                builder: (context, _) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final val = (_waveController.value + (index * 0.2)) % 1.0;
                      final h = (_isAiSpeaking || _isListening) ? 14.0 + (val * 24.0) : 8.0;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 5,
                        height: h,
                        decoration: BoxDecoration(
                          color: _isAiSpeaking ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                _statusMessage,
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),

        // Live Conversation Transcript Box
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF131C2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length + (_currentSpokenText.isNotEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < _messages.length) {
                  final msg = _messages[index];
                  final isAi = msg['role'] == 'assistant';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: isAi ? emerald.withValues(alpha: 0.2) : Colors.indigo.withValues(alpha: 0.2),
                          child: Icon(
                            isAi ? Icons.smart_toy_rounded : Icons.person_rounded,
                            size: 14,
                            color: isAi ? emerald : Colors.indigoAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isAi ? 'SmartBuddy AI' : 'You',
                                style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                msg['text'] ?? '',
                                style: GoogleFonts.outfit(fontSize: 13, color: Colors.white, height: 1.3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.indigo,
                          child: Icon(Icons.mic, size: 14, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$_currentSpokenText...',
                            style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade300, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
        ),

        if (_isListening || _currentSpokenText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _currentSpokenText.trim().isNotEmpty
                    ? () => _onUserFinishedSpeaking()
                    : null,
                icon: const Icon(Icons.send_rounded, size: 16),
                label: Text(
                  _currentSpokenText.trim().isNotEmpty
                      ? 'Done Speaking (Send Response)'
                      : 'Listening... (Speak your answer)',
                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: emerald,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white10,
                  disabledForegroundColor: Colors.grey.shade400,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: _currentSpokenText.trim().isNotEmpty ? 4 : 0,
                ),
              ),
            ),
          )
        else if (_isProcessing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: emerald),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'AI Thinking...',
                    style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade300),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 10),

        // In-Call Controls Footer
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mute Button
              IconButton.filledTonal(
                onPressed: _toggleMute,
                iconSize: 28,
                style: IconButton.styleFrom(
                  backgroundColor: _isMuted ? Colors.red.withValues(alpha: 0.2) : Colors.white12,
                  foregroundColor: _isMuted ? Colors.redAccent : Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
                icon: Icon(_isMuted ? Icons.mic_off_rounded : Icons.mic_rounded),
                tooltip: _isMuted ? 'Unmute' : 'Mute',
              ),

              // End Call (Red Button)
              InkWell(
                onTap: () => _endCall(status: 'completed'),
                borderRadius: BorderRadius.circular(40),
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0x66EF4444), blurRadius: 16, spreadRadius: 2),
                    ],
                  ),
                  child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 32),
                ),
              ),

              // Speakerphone Toggle
              IconButton.filledTonal(
                onPressed: _toggleSpeaker,
                iconSize: 28,
                style: IconButton.styleFrom(
                  backgroundColor: _isSpeakerOn ? emerald.withValues(alpha: 0.2) : Colors.white12,
                  foregroundColor: _isSpeakerOn ? emerald : Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
                icon: Icon(_isSpeakerOn ? Icons.volume_up_rounded : Icons.phone_in_talk_rounded),
                tooltip: _isSpeakerOn ? 'Speakerphone On' : 'Earpiece Mode',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
