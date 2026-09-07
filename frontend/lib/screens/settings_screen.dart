import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_screen.dart';
import 'notification_control_screen.dart';
import 'ai_keys_settings_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _username;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (user.displayName != null && user.displayName!.isNotEmpty) {
      setState(() {
        _username = user.displayName;
      });
    }

    try {
      final query = await FirebaseFirestore.instance
          .collection('usernames')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        final name = doc.id; // Document ID is the lowercased username
        setState(() {
          _username = name;
        });
      }
    } catch (e) {
      debugPrint('Error loading username: $e');
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Sign Out', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to sign out of RemindBuddy?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        setState(() {
          _username = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully signed out')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF0B0F19) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF161E2E) : Colors.white;
    final cardBorder = isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.06);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Settings & Preferences',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: textColor,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          // ====================================================================
          // 1. HERO PROFILE CARD
          // ====================================================================
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E1B4B), const Color(0xFF0F172A)]
                    : [const Color(0xFFEEF2FF), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? const Color(0xFF4F46E5).withValues(alpha: 0.3) : const Color(0xFF6366F1).withValues(alpha: 0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black.withValues(alpha: 0.4) : const Color(0xFF6366F1).withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar Circle with Glow
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          (user != null && (_username != null || user.email != null))
                              ? ((_username ?? user.email)!.substring(0, 1).toUpperCase())
                              : '👤',
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // User Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user != null ? (_username ?? 'RemindBuddy User') : 'Guest Mode',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            user?.email ?? 'Sign in to sync your data across devices',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: subtextColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          // Cloud Sync Status Pill
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: user != null ? const Color(0xFF10B981) : Colors.amber,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                user != null ? 'Cloud Sync Active' : 'Offline Storage',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: user != null ? const Color(0xFF10B981) : Colors.amber,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Profile Action Button
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AuthScreen()),
                    ).then((_) {
                      setState(() {});
                      _loadUsername();
                    });
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFF6366F1).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFF6366F1).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          user != null ? Icons.manage_accounts_rounded : Icons.login_rounded,
                          size: 18,
                          color: isDark ? Colors.cyanAccent : const Color(0xFF4F46E5),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          user != null ? 'Manage Account & Profile' : 'Sign In / Register',
                          style: GoogleFonts.outfit(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.cyanAccent : const Color(0xFF4F46E5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ====================================================================
          // 2. SECTION: AI & SMART INTEGRATIONS
          // ====================================================================
          _buildSectionHeader('AI & INTELLIGENCE 🤖', subtextColor),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cardBorder),
            ),
            child: _buildModernTile(
              icon: Icons.vpn_key_rounded,
              iconGradient: const [Color(0xFF06B6D4), Color(0xFF0284C7)],
              title: 'AI & Search Keys (BYOK)',
              subtitle: 'Configure your Gemini & Tavily keys for Voice, Jobs & Events',
              badgeText: 'BYOK',
              badgeColor: const Color(0xFF06B6D4),
              isFirst: true,
              isLast: true,
              textColor: textColor,
              subtextColor: subtextColor,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AIKeysSettingsScreen()),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // ====================================================================
          // 3. SECTION: INTERFACE & NOTIFICATIONS
          // ====================================================================
          _buildSectionHeader('CUSTOMIZATION & ALERTS 🎨', subtextColor),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              children: [
                _buildModernTile(
                  icon: Icons.dashboard_customize_rounded,
                  iconGradient: const [Color(0xFFA855F7), Color(0xFF7C3AED)],
                  title: 'Customize Bottom Bar',
                  subtitle: 'Select which feature tabs appear on your navigation bar',
                  isFirst: true,
                  isLast: false,
                  textColor: textColor,
                  subtextColor: subtextColor,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(context, 'customize_bottom_bar');
                  },
                ),
                Divider(height: 1, indent: 64, color: cardBorder),
                _buildModernTile(
                  icon: Icons.notifications_active_rounded,
                  iconGradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
                  title: 'Notification Control',
                  subtitle: 'Fine-tune push and email alerts for every feature',
                  isFirst: false,
                  isLast: true,
                  textColor: textColor,
                  subtextColor: subtextColor,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const NotificationControlScreen()),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ====================================================================
          // 4. SECTION: SYSTEM & UPDATES
          // ====================================================================
          _buildSectionHeader('APP & ABOUT ℹ️', subtextColor),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              children: [
                if (!kIsWeb) ...[
                  _buildModernTile(
                    icon: Icons.system_update_alt_rounded,
                    iconGradient: const [Color(0xFF6366F1), Color(0xFF4338CA)],
                    title: 'Check for Updates',
                    subtitle: 'Check for the latest stable version of RemindBuddy',
                    isFirst: true,
                    isLast: false,
                    textColor: textColor,
                    subtextColor: subtextColor,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      UpdateService.checkForUpdates(context, showNoUpdateMsg: true);
                    },
                  ),
                  Divider(height: 1, indent: 64, color: cardBorder),
                ],
                _buildModernTile(
                  icon: Icons.verified_rounded,
                  iconGradient: const [Color(0xFF10B981), Color(0xFF059669)],
                  title: 'RemindBuddy Engine',
                  subtitle: 'All-in-One AI Daily Life & Assistant Platform',
                  badgeText: 'v1.10.19',
                  badgeColor: const Color(0xFF10B981),
                  isFirst: kIsWeb,
                  isLast: true,
                  textColor: textColor,
                  subtextColor: subtextColor,
                  onTap: () {},
                ),
              ],
            ),
          ),

          // ====================================================================
          // 5. SIGN OUT BUTTON (If authenticated)
          // ====================================================================
          if (user != null) ...[
            const SizedBox(height: 28),
            InkWell(
              onTap: () {
                HapticFeedback.mediumImpact();
                _confirmLogout();
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Sign Out',
                      style: GoogleFonts.outfit(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 36),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: color,
        ),
      ),
    );
  }

  Widget _buildModernTile({
    required IconData icon,
    required List<Color> iconGradient,
    required String title,
    required String subtitle,
    String? badgeText,
    Color? badgeColor,
    required bool isFirst,
    required bool isLast,
    required Color textColor,
    required Color subtextColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(20) : Radius.zero,
        bottom: isLast ? const Radius.circular(20) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        child: Row(
          children: [
            // Micro-icon container with gradient
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: iconGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: iconGradient.first.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            // Title & Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      color: subtextColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (badgeText != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (badgeColor ?? Colors.blue).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (badgeColor ?? Colors.blue).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  badgeText,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: badgeColor ?? Colors.blue,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 20, color: subtextColor.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}
