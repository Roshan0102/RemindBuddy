import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/bank_account.dart';
import '../models/finance_transaction.dart';
import '../models/sms_transaction.dart';
import '../services/finance_service.dart';
import '../screens/ai_keys_settings_screen.dart';

class VoiceExpenseLoggerSheet extends StatefulWidget {
  final List<BankAccount> accounts;
  final List<String> customCategories;
  final VoidCallback? onTransactionsAdded;

  const VoiceExpenseLoggerSheet({
    super.key,
    required this.accounts,
    this.customCategories = const [],
    this.onTransactionsAdded,
  });

  @override
  State<VoiceExpenseLoggerSheet> createState() => _VoiceExpenseLoggerSheetState();
}

enum _VoiceSheetState { listening, processing, review, saving }

class _ParsedItem {
  TextEditingController titleController;
  TextEditingController amountController;
  TextEditingController notesController;
  String type; // 'debit' or 'credit'
  String category;
  String? accountId;

  _ParsedItem({
    required String title,
    required double amount,
    required this.type,
    required this.category,
    this.accountId,
    String notes = '',
  })  : titleController = TextEditingController(text: title),
        amountController = TextEditingController(text: amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)),
        notesController = TextEditingController(text: notes);

  void dispose() {
    titleController.dispose();
    amountController.dispose();
    notesController.dispose();
  }
}

class _VoiceExpenseLoggerSheetState extends State<VoiceExpenseLoggerSheet> with SingleTickerProviderStateMixin {
  final SpeechToText _speechToText = SpeechToText();
  final FinanceService _financeService = FinanceService();

  _VoiceSheetState _state = _VoiceSheetState.listening;
  String _liveTranscript = '';
  String _errorMessage = '';
  bool _needsGeminiKey = false;
  String? _modelUsed;

  late AnimationController _pulseController;
  final List<_ParsedItem> _parsedItems = [];

  Timer? _autoConfirmTimer;
  int _autoConfirmCountdown = 3;
  bool _isAutoConfirmActive = false;

  final List<String> _baseCategories = [
    'Food & Dining',
    'Fuel & Travel',
    'Groceries',
    'Bills & Utilities',
    'Shopping',
    'Personal Transfer',
    'Self Transfer',
    'Entertainment',
    'Medical & Health',
    'Personal Care',
    'Salary / Income',
    'Borrowed',
    'Lended',
    'Others',
  ];

  List<String> get _allCategories {
    final Set<String> set = Set.from(_baseCategories);
    set.addAll(widget.customCategories);
    return set.toList();
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _startListening();
  }

  @override
  void dispose() {
    _autoConfirmTimer?.cancel();
    _speechToText.stop();
    _pulseController.dispose();
    for (final item in _parsedItems) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _startListening() async {
    setState(() {
      _state = _VoiceSheetState.listening;
      _liveTranscript = '';
      _errorMessage = '';
      _needsGeminiKey = false;
    });

    final available = await _speechToText.initialize(
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _errorMessage = "Speech recognition error: ${err.errorMsg}";
        });
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (_state == _VoiceSheetState.listening && _liveTranscript.trim().isNotEmpty) {
            _processVoiceInput(_liveTranscript);
          }
        }
      },
    );

    if (available) {
      await _speechToText.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _liveTranscript = result.recognizedWords;
          });
          if (result.finalResult && _liveTranscript.trim().isNotEmpty) {
            _speechToText.stop();
            _processVoiceInput(_liveTranscript);
          }
        },
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 45),
          pauseFor: const Duration(seconds: 3),
          cancelOnError: false,
          partialResults: true,
        ),
      );
    } else {
      if (!mounted) return;
      setState(() {
        _errorMessage = "Microphone access or Speech recognition not available.";
      });
    }
  }

  Future<void> _stopAndProcessManually() async {
    await _speechToText.stop();
    if (_liveTranscript.trim().isNotEmpty) {
      _processVoiceInput(_liveTranscript);
    } else {
      setState(() {
        _errorMessage = "No speech detected. Please tap mic to try again.";
      });
    }
  }

  Future<void> _processVoiceInput(String transcript) async {
    if (transcript.trim().isEmpty) return;

    setState(() {
      _state = _VoiceSheetState.processing;
      _errorMessage = '';
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'parseVoiceExpensesWithAI',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

      final accountsPayload = widget.accounts.map((a) => {'id': a.id, 'name': a.name}).toList();

      final res = await callable.call({
        'transcript': transcript.trim(),
        'accounts': accountsPayload,
        'customCategories': widget.customCategories,
      });

      final data = res.data as Map<String, dynamic>?;
      if (data == null || data['success'] != true) {
        throw Exception(data?['message'] ?? 'Could not extract transactions from voice.');
      }

      _modelUsed = data['modelUsed'] as String?;
      final rawList = data['transactions'] as List? ?? [];

      if (rawList.isEmpty) {
        setState(() {
          _state = _VoiceSheetState.listening;
          _errorMessage = "No transactions found in speech. Try saying: 'I spent 50 on coffee and 200 on fuel'";
        });
        return;
      }

      // Dispose existing
      for (final it in _parsedItems) {
        it.dispose();
      }
      _parsedItems.clear();

      for (final raw in rawList) {
        final map = Map<String, dynamic>.from(raw);
        final spokenAccountName = (map['account'] ?? '').toString().toLowerCase();

        String? matchedAccountId;
        if (widget.accounts.isNotEmpty) {
          if (spokenAccountName.isNotEmpty) {
            for (final acc in widget.accounts) {
              if (acc.name.toLowerCase().contains(spokenAccountName) ||
                  spokenAccountName.contains(acc.name.toLowerCase())) {
                matchedAccountId = acc.id;
                break;
              }
            }
          }
          matchedAccountId ??= widget.accounts.first.id;
        }

        final rawCat = (map['category'] ?? 'Others').toString();
        final matchedCat = _allCategories.contains(rawCat) ? rawCat : 'Others';

        _parsedItems.add(_ParsedItem(
          title: (map['title'] ?? 'Expense').toString(),
          amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
          type: (map['type'] ?? 'debit').toString().toLowerCase() == 'credit' ? 'credit' : 'debit',
          category: matchedCat,
          accountId: matchedAccountId,
          notes: (map['notes'] ?? '').toString(),
        ));
      }

      if (!mounted) return;
      setState(() {
        _state = _VoiceSheetState.review;
      });

      // Start 3-second auto-confirm countdown
      _startAutoConfirmTimer();
    } catch (e) {
      if (!mounted) return;
      final errStr = e.toString();
      final isKeyError = errStr.contains('Gemini API Key') || errStr.contains('failed-precondition');
      setState(() {
        _state = _VoiceSheetState.listening;
        _errorMessage = isKeyError
            ? "Your personal Gemini API Key is required for voice logging. Please add it in AI Keys Settings."
            : "Extraction error: $e";
        _needsGeminiKey = isKeyError;
      });
    }
  }

  void _startAutoConfirmTimer() {
    _autoConfirmTimer?.cancel();
    _autoConfirmCountdown = 3;
    _isAutoConfirmActive = true;

    _autoConfirmTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_autoConfirmCountdown > 1) {
        setState(() => _autoConfirmCountdown--);
      } else {
        timer.cancel();
        _saveAllTransactions();
      }
    });
  }

  void _pauseAutoConfirm() {
    if (_isAutoConfirmActive) {
      _autoConfirmTimer?.cancel();
      setState(() {
        _isAutoConfirmActive = false;
      });
    }
  }

  Future<void> _saveAllTransactions() async {
    _autoConfirmTimer?.cancel();
    if (_parsedItems.isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      _state = _VoiceSheetState.saving;
    });

    try {
      final now = DateTime.now();

      await Future.wait(_parsedItems.map((item) async {
        final amt = double.tryParse(item.amountController.text.trim()) ?? 0.0;
        if (amt <= 0) return;

        final title = item.titleController.text.trim().isNotEmpty
            ? item.titleController.text.trim()
            : item.category;
        final notes = item.notesController.text.trim();
        final isDebit = item.type == 'debit';

        BankAccount? matchedAccount;
        if (item.accountId != null) {
          try {
            matchedAccount = widget.accounts.firstWhere((a) => a.id == item.accountId);
          } catch (_) {}
        }

        // 1. Record in finance_transactions (updates balance)
        if (item.accountId != null && item.accountId!.isNotEmpty) {
          await _financeService.addTransaction(FinanceTransaction(
            id: '',
            accountId: item.accountId!,
            type: isDebit ? 'expense' : 'income',
            amount: amt,
            category: item.category,
            note: notes.isNotEmpty ? notes : title,
            timestamp: now,
          ));
        }

        // 2. Also record in sms_transactions for Smart Bank Tracker
        final manualSms = SmsTransaction(
          id: '',
          sender: matchedAccount?.name ?? 'Voice Log',
          bankName: matchedAccount?.name ?? 'Voice Log',
          accountLast4: 'Voice',
          type: isDebit ? 'Debit' : 'Credit',
          amount: amt,
          payee: title,
          timestamp: now,
          isVerified: true,
          category: item.category,
          notes: notes.isNotEmpty ? notes : 'Voice Logged',
          source: 'manual',
          sourceApp: 'Voice Logger',
          rawBody: 'Voice Logged (${item.type.toUpperCase()}) - $title (₹$amt)',
        );

        await _financeService.addManualSmsTransaction(manualSms, destinationBankAccountId: null);
      }));

      widget.onTransactionsAdded?.call();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Successfully logged ${_parsedItems.length} transaction(s)!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _VoiceSheetState.review;
          _errorMessage = "Failed to save: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final text = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtext = isDark ? Colors.white60 : Colors.black54;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Voice Expense Logger',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: text),
                        ),
                        Text(
                          _modelUsed != null ? 'Extracted via $_modelUsed' : 'Natural Multi-Expense Dictation',
                          style: TextStyle(fontSize: 11, color: isDark ? Colors.purpleAccent.shade100 : Colors.purple.shade700),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Dynamic Body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildStateContent(isDark, cardBg, text, subtext),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateContent(bool isDark, Color cardBg, Color text, Color subtext) {
    if (_state == _VoiceSheetState.listening) {
      return _buildListeningView(isDark, text, subtext);
    } else if (_state == _VoiceSheetState.processing) {
      return _buildProcessingView(isDark, text, subtext);
    } else if (_state == _VoiceSheetState.saving) {
      return _buildSavingView(text, subtext);
    } else {
      return _buildReviewView(isDark, cardBg, text, subtext);
    }
  }

  Widget _buildListeningView(bool isDark, Color text, Color subtext) {
    return Column(
      children: [
        const SizedBox(height: 12),
        // Pulsing Wave/Mic Icon
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = 1.0 + (_pulseController.value * 0.18);
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.45 * _pulseController.value),
                      blurRadius: 24,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(Icons.mic_rounded, size: 42, color: Colors.white),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        Text(
          'Listening...',
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: text),
        ),
        const SizedBox(height: 6),
        Text(
          'Say all your expenses at once! For example:',
          style: TextStyle(fontSize: 13, color: subtext),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          ),
          child: Text(
            '"I paid 50 for breakfast, 200 for petrol via HDFC, and got 500 from Rahul"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: isDark ? Colors.amberAccent.shade100 : Colors.indigo.shade800,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Live Transcript Box
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 70),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
          child: Text(
            _liveTranscript.isEmpty ? 'Your speech will appear here in real time...' : _liveTranscript,
            style: TextStyle(
              fontSize: 14,
              color: _liveTranscript.isEmpty ? subtext : text,
              fontWeight: _liveTranscript.isEmpty ? FontWeight.normal : FontWeight.w500,
            ),
          ),
        ),

        if (_errorMessage.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.redAccent.shade100),
            ),
            child: Column(
              children: [
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: Colors.redAccent),
                ),
                if (_needsGeminiKey) ...[
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (c) => const AIKeysSettingsScreen()),
                      );
                    },
                    icon: const Icon(Icons.vpn_key_rounded, size: 16),
                    label: const Text('Open AI Keys Settings'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purpleAccent.shade700,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _startListening,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Restart'),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: _stopAndProcessManually,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('Done Speaking ⚡'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProcessingView(bool isDark, Color text, Color subtext) {
    return Column(
      children: [
        const SizedBox(height: 40),
        const SizedBox(
          width: 50,
          height: 50,
          child: CircularProgressIndicator(
            strokeWidth: 3.5,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Gemini Flash is Parsing Spends...',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: text),
        ),
        const SizedBox(height: 8),
        Text(
          'Extracting categories, amounts, payment modes & types in ~1 second',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: subtext),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildSavingView(Color text, Color subtext) {
    return Column(
      children: [
        const SizedBox(height: 40),
        const SizedBox(
          width: 50,
          height: 50,
          child: CircularProgressIndicator(
            strokeWidth: 3.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Saving to Smart Bank Tracker...',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: text),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildReviewView(bool isDark, Color cardBg, Color text, Color subtext) {
    final debitCount = _parsedItems.where((i) => i.type == 'debit').length;
    final creditCount = _parsedItems.where((i) => i.type == 'credit').length;

    final debitTotal = _parsedItems
        .where((i) => i.type == 'debit')
        .fold(0.0, (t, i) => t + (double.tryParse(i.amountController.text) ?? 0.0));
    final creditTotal = _parsedItems
        .where((i) => i.type == 'credit')
        .fold(0.0, (t, i) => t + (double.tryParse(i.amountController.text) ?? 0.0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary & Auto-Confirm Banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? Colors.indigo.shade800 : Colors.indigo.shade100),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Extracted ${_parsedItems.length} Transaction(s)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  if (_isAutoConfirmActive)
                    InkWell(
                      onTap: _pauseAutoConfirm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade700,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.pause, size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              'Auto-saving in $_autoConfirmCountdown s',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    const Text('Auto-save paused', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (debitCount > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$debitCount Debit (₹${debitTotal.toStringAsFixed(0)})',
                        style: const TextStyle(fontSize: 11.5, color: Colors.redAccent, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (creditCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$creditCount Credit (₹${creditTotal.toStringAsFixed(0)})',
                        style: const TextStyle(fontSize: 11.5, color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Item Cards
        ..._parsedItems.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: cardBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: item.type == 'debit' ? Colors.redAccent.withValues(alpha: 0.25) : Colors.green.withValues(alpha: 0.25),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Debit / Credit selector
                      GestureDetector(
                        onTap: () {
                          _pauseAutoConfirm();
                          setState(() {
                            item.type = item.type == 'debit' ? 'credit' : 'debit';
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: item.type == 'debit' ? Colors.red.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item.type == 'debit' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                size: 14,
                                color: item.type == 'debit' ? Colors.redAccent : Colors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                item.type == 'debit' ? 'Debit (Expense)' : 'Credit (Income)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: item.type == 'debit' ? Colors.redAccent : Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _pauseAutoConfirm();
                          setState(() {
                            item.dispose();
                            _parsedItems.removeAt(idx);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      // Amount input
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: item.amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => _pauseAutoConfirm(),
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                            prefixText: '₹ ',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Title
                      Expanded(
                        flex: 5,
                        child: TextField(
                          controller: item.titleController,
                          onChanged: (_) => _pauseAutoConfirm(),
                          style: const TextStyle(fontSize: 14),
                          decoration: const InputDecoration(
                            labelText: 'Title / Payee',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Row(
                    children: [
                      // Category Dropdown
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _allCategories.contains(item.category) ? item.category : 'Others',
                          isDense: true,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          items: _allCategories.map((c) {
                            return DropdownMenuItem(
                              value: c,
                              child: Text(c, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              _pauseAutoConfirm();
                              setState(() => item.category = val);
                            }
                          },
                        ),
                      ),
                      if (widget.accounts.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        // Account Dropdown
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: widget.accounts.any((a) => a.id == item.accountId)
                                ? item.accountId
                                : widget.accounts.first.id,
                            isDense: true,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Account',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            items: widget.accounts.map((a) {
                              return DropdownMenuItem(
                                value: a.id,
                                child: Text(a.name, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                _pauseAutoConfirm();
                                setState(() => item.accountId = val);
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 8),

        // Bottom Actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  _autoConfirmTimer?.cancel();
                  _startListening();
                },
                icon: const Icon(Icons.mic_rounded, size: 16),
                label: const Text('Speak Again'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _saveAllTransactions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: Text(
                  _isAutoConfirmActive
                      ? 'Confirm All ($_autoConfirmCountdown s)'
                      : 'Confirm & Save (${_parsedItems.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
