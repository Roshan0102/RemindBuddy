import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class AIKeysSettingsScreen extends StatefulWidget {
  const AIKeysSettingsScreen({super.key});

  @override
  State<AIKeysSettingsScreen> createState() => _AIKeysSettingsScreenState();
}

class _AIKeysSettingsScreenState extends State<AIKeysSettingsScreen> {
  final _geminiController = TextEditingController();
  final _tavilyController = TextEditingController();

  bool _obscureGemini = true;
  bool _obscureTavily = true;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadUserApiKeys();
  }

  @override
  void dispose() {
    _geminiController.dispose();
    _tavilyController.dispose();
    super.dispose();
  }

  Future<void> _loadUserApiKeys() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final userKeys = data['userApiKeys'] as Map<String, dynamic>? ?? {};
        _geminiController.text = (userKeys['geminiApiKey'] ?? data['geminiApiKey'] ?? '').toString();
        _tavilyController.text = (userKeys['tavilyApiKey'] ?? data['tavilyApiKey'] ?? '').toString();
      }
    } catch (e) {
      debugPrint('Error loading user API keys: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveUserApiKeys() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to save your API keys.')),
      );
      return;
    }

    final geminiKey = _geminiController.text.trim();
    final tavilyKey = _tavilyController.text.trim();

    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'userApiKeys': {
          'geminiApiKey': geminiKey,
          'tavilyApiKey': tavilyKey,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'geminiApiKey': geminiKey,
        'tavilyApiKey': tavilyKey,
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ API keys saved successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save API keys: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _pasteTo(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        controller.text = data.text!.trim();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pasted from clipboard'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openUrl(String urlString) async {
    final uri = Uri.parse(urlString);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI & Search Keys (BYOK)'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Info Banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.teal.withValues(alpha: 0.15),
                        Colors.blueAccent.withValues(alpha: 0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.vpn_key_rounded, color: Colors.teal, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Bring Your Own Keys (BYOK)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Powers your personal Auto-Apply Job Agent, Tech Events & Walk-In Drives with your own free tier limits. Stored securely in your private user profile.',
                              style: TextStyle(fontSize: 12.5, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8), height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 1. Google Gemini API Key Section
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.auto_awesome, color: Colors.blueAccent, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Google Gemini API Key',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Used to parse job posts, match your master resume, and format cover letters.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _geminiController,
                          obscureText: _obscureGemini,
                          decoration: InputDecoration(
                            labelText: 'Gemini API Key',
                            hintText: 'AIzaSy...',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.key_rounded, color: Colors.blueAccent),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(_obscureGemini ? Icons.visibility_off : Icons.visibility),
                                  onPressed: () => setState(() => _obscureGemini = !_obscureGemini),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.paste_rounded),
                                  tooltip: 'Paste',
                                  onPressed: () => _pasteTo(_geminiController),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _openUrl('https://aistudio.google.com/app/apikey'),
                            icon: const Icon(Icons.open_in_new, size: 14),
                            label: const Text('Get Free Key (Google AI Studio)', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Tavily Search API Key Section
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.travel_explore_rounded, color: Colors.teal, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Tavily Search API Key',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Used for real-time web discovery of live recruiter emails, tech meetups, and walk-in drives.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _tavilyController,
                          obscureText: _obscureTavily,
                          decoration: InputDecoration(
                            labelText: 'Tavily API Key',
                            hintText: 'tvly-dev-...',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.search_rounded, color: Colors.teal),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(_obscureTavily ? Icons.visibility_off : Icons.visibility),
                                  onPressed: () => setState(() => _obscureTavily = !_obscureTavily),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.paste_rounded),
                                  tooltip: 'Paste',
                                  onPressed: () => _pasteTo(_tavilyController),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _openUrl('https://app.tavily.com'),
                            icon: const Icon(Icons.open_in_new, size: 14),
                            label: const Text('Get Free Key (1,000 Searches/Month)', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Save Button
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveUserApiKeys,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(_isSaving ? 'Saving...' : 'Save API Keys', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
    );
  }
}
