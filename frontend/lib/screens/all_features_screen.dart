import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AllFeaturesScreen extends StatelessWidget {
  final Function(String featureId) onSelectFeature;

  const AllFeaturesScreen({super.key, required this.onSelectFeature});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final List<Map<String, dynamic>> features = [
      {
        'id': 'gold',
        'title': 'Gold Rates',
        'category': 'MARKET & INVESTMENTS',
        'icon': Icons.monetization_on_rounded,
        'color': Colors.amber.shade700,
        'description': 'Live 22K/24K gold rates, AI chit advice, and price alerts.',
      },
      {
        'id': 'finance',
        'title': 'FinanceBuddy',
        'category': 'PERSONAL FINANCE',
        'icon': Icons.account_balance_wallet_rounded,
        'color': Colors.teal.shade600,
        'description': 'Track bank balances, bills, debts, and group trip bill splitting.',
      },
      {
        'id': 'job_assistant',
        'title': 'AI Job Assistant',
        'category': 'CAREER & AI',
        'icon': Icons.work_rounded,
        'color': Colors.blueAccent.shade700,
        'description': 'Extract HR emails from screenshots, draft cover letters & send applications.',
      },
      {
        'id': 'reminders',
        'title': 'Reminders & Calendar',
        'category': 'PRODUCTIVITY',
        'icon': Icons.calendar_today_rounded,
        'color': Colors.indigo.shade600,
        'description': 'Smart calendar reminders, auto-snooze, and task management.',
      },
      {
        'id': 'notes',
        'title': 'Notes & Checklists',
        'category': 'PRODUCTIVITY',
        'icon': Icons.note_alt_rounded,
        'color': Colors.teal.shade700,
        'description': 'Rich text notes, pinned checklists, and quick capture.',
      },
      {
        'id': 'shifts',
        'title': 'My Shifts',
        'category': 'WORK & SCHEDULE',
        'icon': Icons.work_history_rounded,
        'color': Colors.orange.shade700,
        'description': 'Work roster management, shift OCR parsing, and alarm sync.',
      },
      {
        'id': 'vault',
        'title': 'Secure Vault',
        'category': 'SECURITY & PASSWORDS',
        'icon': Icons.shield_rounded,
        'color': Colors.blue.shade800,
        'description': 'Encrypted passwords, documents, and private vault notes.',
      },
      {
        'id': 'gcp_cost',
        'title': 'GCP Cost Tracker',
        'category': 'CLOUD & INFRA',
        'icon': Icons.attach_money_rounded,
        'color': Colors.green.shade700,
        'description': 'Track GCP Cloud usage, historical monthly spend, and credits in INR.',
      },
      {
        'id': 'astro_calendar',
        'title': 'Astro Calendar',
        'category': 'UTILITIES',
        'icon': Icons.wb_sunny_rounded,
        'color': Colors.deepOrange.shade600,
        'description': 'Daily astronomical calendar, auspicious times, and moon phases.',
      },
      {
        'id': 'daily_reminders',
        'title': 'Daily Habit Alarms',
        'category': 'UTILITIES',
        'icon': Icons.alarm_on_rounded,
        'color': Colors.purple.shade600,
        'description': 'Recurring daily habit check-ins and alarm reminders.',
      },
      {
        'id': 'events',
        'title': 'Tech Events',
        'category': 'CAREER',
        'icon': Icons.event_available_rounded,
        'color': Colors.cyan.shade700,
        'description': 'Discover upcoming tech conferences, hackathons, and webinars.',
      },
      {
        'id': 'walkins',
        'title': 'Walk-In Drives',
        'category': 'CAREER',
        'icon': Icons.directions_walk_rounded,
        'color': Colors.lightBlue.shade700,
        'description': 'Explore walk-in job interview drives and venue details.',
      },
      {
        'id': 'voice_assistant',
        'title': 'Voice Assistant',
        'category': 'AI UTILITY',
        'icon': Icons.mic_rounded,
        'color': Colors.pink.shade600,
        'description': 'Voice-command assistant powered by Gemini AI.',
      },
      {
        'id': 'notifications',
        'title': 'Notification History',
        'category': 'SYSTEM',
        'icon': Icons.notifications_active_rounded,
        'color': Colors.deepPurple.shade600,
        'description': 'View log history of all past push notifications.',
      },
      {
        'id': 'settings',
        'title': 'Settings & Theme',
        'category': 'SYSTEM',
        'icon': Icons.settings_rounded,
        'color': Colors.blueGrey.shade700,
        'description': 'Manage dark mode, profile settings, and app preferences.',
      },
    ];

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.grid_view_rounded, size: 28, color: Colors.blue.shade900),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'All Applications & Features',
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          Text(
                            'Explore all tools, utilities, and AI modules in RemindBuddy.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white60 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                mainAxisExtent: 170,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final feat = features[index];
                  final color = feat['color'] as Color;

                  return InkWell(
                    onTap: () => onSelectFeature(feat['id'] as String),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.grey.shade200,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(feat['icon'] as IconData, color: color, size: 24),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      feat['category'] as String,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: color,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      feat['title'] as String,
                                      style: GoogleFonts.outfit(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Text(
                              feat['description'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : Colors.grey.shade700,
                                height: 1.3,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: features.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
