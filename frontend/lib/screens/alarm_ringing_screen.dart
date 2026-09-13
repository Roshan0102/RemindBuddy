import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/calendar_reminder.dart';
import '../services/alarm_audio_service.dart';
import '../services/notification_service.dart';

class AlarmRingingScreen extends StatefulWidget {
  final CalendarReminder reminder;

  const AlarmRingingScreen({super.key, required this.reminder});

  @override
  State<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends State<AlarmRingingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Timer _clockTimer;
  DateTime _currentTime = DateTime.now();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _clockTimer.cancel();
    super.dispose();
  }

  Future<void> _dismissAlarm() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    await AlarmAudioService().stopAlarm();
    if (widget.reminder.id != null) {
      NotificationService().cancelNotification(widget.reminder.id.hashCode);
    }

    // Mark reminder completed in Firestore
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && widget.reminder.id != null) {
      try {
        final docRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('calendar_reminders')
            .doc(widget.reminder.id);

        final expireAt = DateTime.now().add(const Duration(days: 30));
        await docRef.update({
          'status': 'completed',
          'notifiedAt': FieldValue.serverTimestamp(),
          'expireAt': Timestamp.fromDate(expireAt),
        });
      } catch (e) {
        debugPrint('[AlarmRingingScreen] Error dismissing reminder: $e');
      }
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _snoozeAlarm() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    await AlarmAudioService().stopAlarm();
    if (widget.reminder.id != null) {
      NotificationService().cancelNotification(widget.reminder.id.hashCode);
    }

    // Snooze reminder 10 minutes
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && widget.reminder.id != null) {
      try {
        final nextTime = DateTime.now().add(const Duration(minutes: 10));
        final dateStr = DateFormat('yyyy-MM-dd').format(nextTime);
        final timeStr = DateFormat('HH:mm').format(nextTime);

        final docRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('calendar_reminders')
            .doc(widget.reminder.id);

        await docRef.update({
          'date': dateStr,
          'time': timeStr,
          'status': 'pending',
          'currentSnoozeCount': widget.reminder.currentSnoozeCount + 1,
        });
      } catch (e) {
        debugPrint('[AlarmRingingScreen] Error snoozing reminder: $e');
      }
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('hh:mm:ss');
    final amPmFormat = DateFormat('a');
    final dateFormat = DateFormat('EEEE, MMMM d, yyyy');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _dismissAlarm();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.2,
                colors: [
                  const Color(0xFFE11D48).withValues(alpha: 0.25),
                  const Color(0xFF0F172A),
                ],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 1. Top Bar / Live Clock
                Column(
                  children: [
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          timeFormat.format(_currentTime),
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          amPmFormat.format(_currentTime),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF43F5E),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(_currentTime),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),

                // 2. Center Pulsing Icon & Reminder Details
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFE11D48).withValues(alpha: 0.15),
                          border: Border.all(
                            color: const Color(0xFFF43F5E).withValues(alpha: 0.5),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE11D48).withValues(alpha: 0.4),
                              blurRadius: 32,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.alarm_rounded,
                            size: 72,
                            color: Color(0xFFF43F5E),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Badge: Location or Time
                    if (widget.reminder.isLocationBased)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFF818CF8)),
                            const SizedBox(width: 6),
                            Text(
                              '📍 Arrived: ${widget.reminder.locationName ?? "Target Location"}',
                              style: const TextStyle(
                                color: Color(0xFF818CF8),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time_filled_rounded, size: 16, color: Color(0xFF38BDF8)),
                            const SizedBox(width: 6),
                            Text(
                              'Scheduled Alarm (${widget.reminder.time})',
                              style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Title
                    Text(
                      widget.reminder.title.isNotEmpty ? widget.reminder.title : 'Reminder Alarm',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),

                    if (widget.reminder.description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        widget.reminder.description,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white.withValues(alpha: 0.75),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),

                // 3. Bottom Action Buttons
                Column(
                  children: [
                    // Big Dismiss Button
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _dismissAlarm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE11D48),
                          foregroundColor: Colors.white,
                          elevation: 8,
                          shadowColor: const Color(0xFFE11D48).withValues(alpha: 0.6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.alarm_off_rounded, size: 28),
                            const SizedBox(width: 12),
                            Text(
                              _isProcessing ? 'Dismissing...' : 'DISMISS ALARM',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Snooze Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _isProcessing ? null : _snoozeAlarm,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.snooze_rounded, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Snooze for 10 minutes',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Volume button hint
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.volume_down_rounded, size: 14, color: Colors.white.withValues(alpha: 0.4)),
                        const SizedBox(width: 6),
                        Text(
                          'Press hardware volume buttons to silence',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
