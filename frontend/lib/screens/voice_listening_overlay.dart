import 'package:flutter/material.dart';
import 'dart:async';
import '../services/voice_assistant_service.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceListeningOverlay extends StatefulWidget {
  const VoiceListeningOverlay({super.key});

  @override
  State<VoiceListeningOverlay> createState() => _VoiceListeningOverlayState();
}

class _VoiceListeningOverlayState extends State<VoiceListeningOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _status = "Listening...";
  StreamSubscription? _subscription;
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    
    // Subscribe to voice assistant updates
    _subscription = VoiceAssistantService().statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _status = status;
        });
      }
    });
    
    // Start listening immediately
    _startVoiceAssistant();
  }

  Future<void> _startVoiceAssistant() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      await VoiceAssistantService().startListening(onResult: (text) {
        VoiceAssistantService().updateStatus("You said: $text");
      });
    } else {
      VoiceAssistantService().updateStatus("Microphone permission denied. You can type your request below!");
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    _textController.dispose();
    VoiceAssistantService().stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.9),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Spacer/Close button row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70, size: 30),
                  ),
                ],
              ),
              
              // Middle Assistant View
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ScaleTransition(
                          scale: Tween(begin: 1.0, end: 1.2).animate(_controller),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withOpacity(0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.blueAccent, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blueAccent.withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                )
                              ],
                            ),
                            child: const Icon(Icons.mic, color: Colors.blueAccent, size: 55),
                          ),
                        ),
                        const SizedBox(height: 40),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Text(
                            _status,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Text fallback input
              Container(
                margin: const EdgeInsets.only(bottom: 12.0),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(30.0),
                  border: Border.all(color: Colors.white.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: const InputDecoration(
                          hintText: "Or type your request here...",
                          hintStyle: TextStyle(color: Colors.white38),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12.0),
                        ),
                        onSubmitted: (value) {
                          if (value.trim().isNotEmpty) {
                            VoiceAssistantService().processCommand(value.trim());
                            _textController.clear();
                            FocusScope.of(context).unfocus();
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.blueAccent),
                      onPressed: () {
                        final value = _textController.text;
                        if (value.trim().isNotEmpty) {
                          VoiceAssistantService().processCommand(value.trim());
                          _textController.clear();
                          FocusScope.of(context).unfocus();
                        }
                      },
                    ),
                  ],
                ),
              ),
              
              // Bottom caption
              const Text(
                "Speak, type above, or tap the X to close",
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
