import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Floating dock widget showing active rest countdown between sets.
/// Features quick time adjustments (+30s / -15s), progress ring, and audio/haptic feedback.
class GymRestTimerWidget extends StatefulWidget {
  final int initialSeconds;
  final VoidCallback onDismiss;
  final VoidCallback? onCompleted;

  const GymRestTimerWidget({
    super.key,
    this.initialSeconds = 90,
    required this.onDismiss,
    this.onCompleted,
  });

  @override
  State<GymRestTimerWidget> createState() => _GymRestTimerWidgetState();
}

class _GymRestTimerWidgetState extends State<GymRestTimerWidget> {
  late int _remainingSeconds;
  late int _totalSeconds;
  Timer? _timer;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    _totalSeconds = widget.initialSeconds;
    _remainingSeconds = widget.initialSeconds;
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 1) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _timer?.cancel();
        setState(() {
          _remainingSeconds = 0;
          _isFinished = true;
        });
        _notifyRestFinished();
      }
    });
  }

  void _notifyRestFinished() {
    // Haptic buzz and alert tone
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    widget.onCompleted?.call();
  }

  void _addSeconds(int seconds) {
    setState(() {
      _remainingSeconds += seconds;
      if (_remainingSeconds > _totalSeconds) {
        _totalSeconds = _remainingSeconds;
      }
      if (_isFinished) {
        _isFinished = false;
        _startTimer();
      }
    });
  }

  void _subtractSeconds(int seconds) {
    setState(() {
      if (_remainingSeconds > seconds) {
        _remainingSeconds -= seconds;
      } else {
        _remainingSeconds = 0;
        _isFinished = true;
        _timer?.cancel();
        _notifyRestFinished();
      }
    });
  }

  String _formatTime(int totalSecs) {
    final mins = (totalSecs ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSecs % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final progress = _totalSeconds > 0
        ? (_remainingSeconds / _totalSeconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _isFinished
            ? (isDark ? const Color(0xFF1B4D3E) : const Color(0xFFE8F5E9))
            : (isDark ? const Color(0xFF1E222A) : Colors.white),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isFinished
              ? Colors.green
              : (isDark ? Colors.blue.withValues(alpha: 0.3) : Colors.blue.withValues(alpha: 0.2)),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Circular Progress Indicator
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: _isFinished ? 1.0 : progress,
                  strokeWidth: 4,
                  backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _isFinished ? Colors.green : theme.colorScheme.primary,
                  ),
                ),
                Center(
                  child: Icon(
                    _isFinished ? Icons.check : Icons.timer,
                    size: 20,
                    color: _isFinished ? Colors.green : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 14),

          // Time & Status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isFinished ? 'REST OVER!' : 'REST TIMER',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: _isFinished ? Colors.green : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isFinished ? 'Ready for next set!' : _formatTime(_remainingSeconds),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _isFinished
                        ? Colors.green
                        : (isDark ? Colors.white : Colors.black87),
                  ),
                ),
              ],
            ),
          ),

          // Adjustment Buttons
          if (!_isFinished) ...[
            _buildSmallButton('-15s', () => _subtractSeconds(15)),
            const SizedBox(width: 6),
            _buildSmallButton('+30s', () => _addSeconds(30)),
            const SizedBox(width: 6),
          ],

          // Dismiss Button
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Dismiss Timer',
            onPressed: widget.onDismiss,
          ),
        ],
      ),
    );
  }

  Widget _buildSmallButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
      ),
    );
  }
}
