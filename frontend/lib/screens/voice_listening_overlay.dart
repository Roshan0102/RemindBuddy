import 'package:flutter/material.dart';
import '../services/voice_assistant_service.dart';

class VoiceListeningOverlay extends StatefulWidget {
  const VoiceListeningOverlay({super.key});

  @override
  State<VoiceListeningOverlay> createState() => _VoiceListeningOverlayState();
}

class _VoiceListeningOverlayState extends State<VoiceListeningOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _status = "Listening...";

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    
    // Start listening immediately
    _startVoiceAssistant();
  }

  Future<void> _startVoiceAssistant() async {
    await VoiceAssistantService().startListening();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.7),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween(begin: 1.0, end: 1.2).animate(_controller),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Colors.blueAccent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic, color: Colors.white, size: 50),
              ),
            ),
            const SizedBox(height: 30),
            Text(
              _status,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 50),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white70, size: 30),
            ),
          ],
        ),
      ),
    );
  }
}
