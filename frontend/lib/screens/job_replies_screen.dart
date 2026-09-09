import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/job_application.dart';
import '../models/networking_lead.dart';
import '../services/job_assistant_service.dart';

class JobRepliesScreen extends StatefulWidget {
  const JobRepliesScreen({super.key});

  @override
  State<JobRepliesScreen> createState() => _JobRepliesScreenState();
}

class _JobRepliesScreenState extends State<JobRepliesScreen> {
  final JobAssistantService _service = JobAssistantService();
  bool _isCheckingReplies = false;
  String _activeFilter = 'all'; // 'all', 'bounced', 'interview_invite', 'founder_chat', 'assessment', 'hr_query'
  bool _showDismissed = false;
  DateTime? _lastChecked;

  late Stream<List<JobApplication>> _applicationsStream;
  late Stream<List<NetworkingLead>> _networkingLeadsStream;

  bool _isDeliveryBounce(String sender, String subject, String bodySnippet, String? responseType) {
    if (responseType == 'bounced') return true;
    final s = sender.toLowerCase();
    final sub = subject.toLowerCase();
    final b = bodySnippet.toLowerCase();
    return s.contains('mailer-daemon') ||
        s.contains('postmaster') ||
        s.contains('delivery subsystem') ||
        sub.contains('delivery status notification') ||
        sub.contains('address not found') ||
        sub.contains('failure notice') ||
        sub.contains('could not be delivered') ||
        b.contains("address couldn't be found") ||
        b.contains('address could not be found') ||
        b.contains('recipient address rejected') ||
        b.contains('delivery failure');
  }

  Future<void> _handleDismissReply(UnifiedReplyItem item) async {
    try {
      await _service.dismissReply(item.id, item.isStartupLead);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Reply marked as handled and cleared from inbox badge.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to dismiss reply: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleDeleteReply(UnifiedReplyItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.isBounced ? 'Delete Delivery Alert?' : 'Delete Reply?'),
        content: Text(
          item.isBounced
              ? 'This will permanently remove this bounce notification from your replies hub.'
              : 'This will remove the recruiter reply from your replies hub and clear the inbox notification.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.deleteReply(item.id, item.isStartupLead);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Reply deleted successfully.'),
            backgroundColor: Colors.blueGrey,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete reply: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleConnectLinkedIn(UnifiedReplyItem item) async {
    if (item.connectionNote != null && item.connectionNote!.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: item.connectionNote!));
    }
    if (item.linkedinUrl != null && item.linkedinUrl!.isNotEmpty) {
      final uri = Uri.tryParse(item.linkedinUrl!);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
    if (item.isStartupLead) {
      await _service.updateNetworkingLeadStatus(item.id, 'note_sent');
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📋 Note copied to clipboard & LinkedIn profile opened!'),
          backgroundColor: Color(0xFF0077B5),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _applicationsStream = _service.getJobApplicationsStream();
    _networkingLeadsStream = _service.getNetworkingLeadsStream();
    _loadLastChecked();
  }

  Future<void> _loadLastChecked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('job_replies_last_checked');
      if (str != null && mounted) {
        setState(() {
          _lastChecked = DateTime.tryParse(str);
        });
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final ts = doc.data()?['lastJobRepliesCheckedAt'];
        if (ts is Timestamp && mounted) {
          final dt = ts.toDate();
          if (_lastChecked == null || dt.isAfter(_lastChecked!)) {
            setState(() {
              _lastChecked = dt;
            });
            await prefs.setString('job_replies_last_checked', dt.toIso8601String());
          }
        }
      }
    } catch (_) {}
  }

  String _formatLastChecked(DateTime dt) {
    final month = DateFormat('MMM').format(dt).toUpperCase();
    final rest = DateFormat('dd, hh:mm a').format(dt);
    return '$month $rest';
  }

  Future<void> _checkRepliesNow() async {
    setState(() {
      _isCheckingReplies = true;
    });

    try {
      final res = await _service.checkJobRepliesNow();
      final repliesFound = res['repliesFound'] ?? 0;
      final checked = res['checked'] ?? 0;

      final now = DateTime.now();
      if (mounted) {
        setState(() {
          _lastChecked = now;
        });
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('job_replies_last_checked', now.toIso8601String());
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'lastJobRepliesCheckedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              repliesFound > 0
                  ? '🎉 Found $repliesFound new reply/replies from recruiters & founders!'
                  : 'Inbox scanned ($checked messages checked). No new replies found.',
            ),
            backgroundColor: repliesFound > 0 ? Colors.green : Colors.blueAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to check inbox: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingReplies = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recruiter & Founder Replies 📬',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (_lastChecked != null)
              Text(
                'Last Checked: ${_formatLastChecked(_lastChecked!)}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark ? const Color(0xFF6EE7B7) : Colors.white70,
                ),
              ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _isCheckingReplies ? null : _checkRepliesNow,
            icon: _isCheckingReplies
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync_rounded, color: Colors.white, size: 18),
            label: Text(
              _isCheckingReplies ? 'Checking...' : 'Check Inbox',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<JobApplication>>(
        initialData: _service.cachedApplications.isNotEmpty ? _service.cachedApplications : null,
        stream: _applicationsStream,
        builder: (context, appSnap) {
          return StreamBuilder<List<NetworkingLead>>(
            initialData: _service.cachedLeads.isNotEmpty ? _service.cachedLeads : null,
            stream: _networkingLeadsStream,
            builder: (context, leadSnap) {
              if (appSnap.connectionState == ConnectionState.waiting &&
                  leadSnap.connectionState == ConnectionState.waiting &&
                  !appSnap.hasData &&
                  !leadSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final allApps = appSnap.data ?? [];
              final allLeads = leadSnap.data ?? [];

              // Filter to items that have received replies or bounced
              final appReplies = allApps.where((a) => a.status == 'reply_received' || a.isBounced).toList();
              final leadReplies = allLeads.where((l) => l.status == 'replied' || l.isBounced).toList();

              // Unified reply list
              final List<UnifiedReplyItem> unifiedReplies = [];

              for (final a in appReplies) {
                final isBounced = a.isBounced || _isDeliveryBounce(a.replySender ?? '', a.replySubject ?? '', a.replySnippet ?? '', a.responseType);
                unifiedReplies.add(UnifiedReplyItem(
                  id: a.id,
                  isStartupLead: false,
                  companyName: a.companyName,
                  roleOrTitle: a.jobTitle,
                  recipientEmail: a.recipientEmail,
                  senderNameOrEmail: a.replySender ?? a.recipientEmail,
                  subject: a.replySubject ?? a.generatedSubject,
                  responseType: isBounced ? 'bounced' : (a.responseType ?? 'hr_query'),
                  summary: a.replySnippet ?? (isBounced ? 'Mail delivery failure: Address not found.' : 'Recruiter replied to your application.'),
                  bodyPreview: a.replyBodyPreview ?? '',
                  actionRequired: isBounced ? 'Check recipient email or find company careers contact' : (a.actionRequired ?? 'Check your email'),
                  receivedAt: a.replyReceivedAt ?? a.appliedAt,
                  isDismissed: a.isReplyDismissed,
                  isBounced: isBounced,
                ));
              }

              for (final l in leadReplies) {
                final isBounced = l.isBounced || _isDeliveryBounce(l.replySender ?? '', l.replySubject ?? '', l.replySnippet ?? '', l.responseType);
                unifiedReplies.add(UnifiedReplyItem(
                  id: l.id,
                  isStartupLead: true,
                  companyName: l.companyName,
                  roleOrTitle: l.currentRole,
                  recipientEmail: l.email ?? '',
                  senderNameOrEmail: l.replySender ?? l.name,
                  subject: l.replySubject ?? l.emailSubject ?? 'Re: Pitch',
                  responseType: isBounced ? 'bounced' : (l.responseType ?? 'founder_chat'),
                  summary: l.replySnippet ?? (isBounced ? 'Delivery failed: Recipient email address was not found by mail server.' : 'Founder replied to your pitch.'),
                  bodyPreview: l.replyBodyPreview ?? '',
                  actionRequired: isBounced ? 'Connect directly on LinkedIn using pre-written note' : (l.actionRequired ?? 'Reply via email'),
                  receivedAt: l.replyReceivedAt ?? l.discoveredAt,
                  linkedinUrl: l.linkedinUrl,
                  connectionNote: l.connectionNote,
                  isDismissed: l.isReplyDismissed,
                  isBounced: isBounced,
                ));
              }

              // Sort by received time descending
              unifiedReplies.sort((x, y) => y.receivedAt.compareTo(x.receivedAt));

              // Active vs All filtering based on _showDismissed
              var displayReplies = _showDismissed
                  ? unifiedReplies
                  : unifiedReplies.where((r) => !r.isDismissed).toList();

              // Filter by responseType
              var filteredReplies = displayReplies;
              if (_activeFilter != 'all') {
                filteredReplies = displayReplies.where((r) => r.responseType == _activeFilter).toList();
              }

              if (unifiedReplies.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.mark_email_unread_rounded, size: 64, color: Colors.blueAccent),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'No Recruiter or Founder Replies Yet',
                          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'When a company or startup replies to your Auto-Apply email or Cold Outreach pitch, RemindBuddy will analyze their response and showcase it here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.4),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _isCheckingReplies ? null : _checkRepliesNow,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Check My Inbox Now'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0077B5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        if (_lastChecked != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.schedule_rounded, size: 14, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(
                                'Last Checked: ${_formatLastChecked(_lastChecked!)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }

              final interviewCount = unifiedReplies.where((r) => r.responseType == 'interview_invite').length;
              final founderCount = unifiedReplies.where((r) => r.responseType == 'founder_chat').length;
              final assessmentCount = unifiedReplies.where((r) => r.responseType == 'assessment').length;
              final bouncedCount = unifiedReplies.where((r) => r.isBounced).length;
              final dismissedCount = unifiedReplies.where((r) => r.isDismissed).length;
              final activeCount = unifiedReplies.where((r) => !r.isDismissed).length;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                              : [const Color(0xFFF0FDF4), const Color(0xFFDCFCE7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.campaign_rounded, color: Colors.green, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$activeCount Active Inquiries & Replies',
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : const Color(0xFF14532D),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$interviewCount Invites • $founderCount Founders • $assessmentCount Assessments${bouncedCount > 0 ? ' • $bouncedCount Bounces' : ''}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? Colors.white70 : Colors.green.shade900,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (_lastChecked != null) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.schedule_rounded,
                                        size: 13,
                                        color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF15803D),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Last Checked: ${_formatLastChecked(_lastChecked!)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF15803D),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _isCheckingReplies ? null : _checkRepliesNow,
                            icon: _isCheckingReplies
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.sync_rounded, size: 16),
                            label: Text(
                              _isCheckingReplies ? 'Checking...' : 'Check Inbox',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Filter Chips & Handled Toggle Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('all', 'All (${_showDismissed ? unifiedReplies.length : activeCount})'),
                          if (bouncedCount > 0) ...[
                            const SizedBox(width: 8),
                            _buildFilterChip('bounced', 'Delivery Alerts ⚠️ ($bouncedCount)'),
                          ],
                          const SizedBox(width: 8),
                          _buildFilterChip('interview_invite', 'Interview Invites 🎯 ($interviewCount)'),
                          const SizedBox(width: 8),
                          _buildFilterChip('founder_chat', 'Founder Chats 🚀 ($founderCount)'),
                          const SizedBox(width: 8),
                          _buildFilterChip('assessment', 'Assessments 📝 ($assessmentCount)'),
                          const SizedBox(width: 8),
                          _buildFilterChip('hr_query', 'HR Messages 💬'),
                          if (dismissedCount > 0) ...[
                            const SizedBox(width: 12),
                            FilterChip(
                              avatar: Icon(
                                _showDismissed ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                size: 15,
                                color: _showDismissed ? Colors.white : Colors.grey,
                              ),
                              label: Text(
                                _showDismissed ? 'Hide Handled' : 'Show Handled ($dismissedCount)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _showDismissed ? Colors.white : null,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              selected: _showDismissed,
                              selectedColor: Colors.blueGrey,
                              onSelected: (val) {
                                setState(() {
                                  _showDismissed = val;
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Reply Cards List
                    if (filteredReplies.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Center(
                          child: Text(
                            'No replies matching the selected filter.',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredReplies.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final item = filteredReplies[index];
                          return _buildReplyCard(item, isDark, cardBg);
                        },
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _activeFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _activeFilter = key;
          });
        }
      },
      selectedColor: const Color(0xFF0077B5),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
    );
  }

  Widget _buildReplyCard(UnifiedReplyItem item, bool isDark, Color cardBg) {
    // Status color mapping
    Color badgeColor;
    String badgeLabel;
    IconData badgeIcon;

    if (item.isBounced) {
      badgeColor = Colors.deepOrange;
      badgeLabel = 'Delivery Failed ⚠️';
      badgeIcon = Icons.error_outline_rounded;
    } else {
      switch (item.responseType) {
        case 'interview_invite':
          badgeColor = Colors.green;
          badgeLabel = 'Interview Invite 🎯';
          badgeIcon = Icons.event_available_rounded;
          break;
        case 'founder_chat':
          badgeColor = Colors.indigoAccent;
          badgeLabel = 'Founder Response 🚀';
          badgeIcon = Icons.rocket_launch_rounded;
          break;
        case 'assessment':
          badgeColor = Colors.orange;
          badgeLabel = 'Coding Assessment 📝';
          badgeIcon = Icons.quiz_rounded;
          break;
        case 'rejection':
          badgeColor = Colors.grey;
          badgeLabel = 'Status Update';
          badgeIcon = Icons.info_outline_rounded;
          break;
        case 'hr_query':
        default:
          badgeColor = Colors.blue;
          badgeLabel = 'Recruiter Message 💬';
          badgeIcon = Icons.chat_rounded;
          break;
      }
    }

    final timeStr = DateFormat('dd MMM yyyy, h:mm a').format(item.receivedAt);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Source Pill, Badge, and Quick Action Icons (Dismiss & Delete)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (item.isStartupLead ? Colors.purple : Colors.blue).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.isStartupLead ? Icons.rocket_launch_rounded : Icons.bolt_rounded,
                      size: 13,
                      color: item.isStartupLead ? Colors.purple : Colors.blue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.isStartupLead ? 'Startup Pitch' : 'Auto-Apply Job',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: item.isStartupLead ? Colors.purple : Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 13, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(
                      badgeLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (item.isDismissed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Handled ✓',
                    style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.done_all_rounded, size: 19),
                  tooltip: 'Mark Handled (Clear Badge)',
                  color: Colors.green,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  onPressed: () => _handleDismissReply(item),
                ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                tooltip: 'Delete Reply',
                color: Colors.redAccent,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
                onPressed: () => _handleDeleteReply(item),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Company & Role
          Text(
            item.companyName,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.roleOrTitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.email_outlined, size: 13, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${item.senderNameOrEmail} • $timeStr',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Bounced Delivery Alert Box
          if (item.isBounced) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.deepOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Address Not Found / Delivery Failure',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The mail server reported that recipient address "${item.recipientEmail.isNotEmpty ? item.recipientEmail : 'target mailbox'}" does not exist or is unable to receive email.',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87, height: 1.3),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '💡 Recommendation: Connect directly with the founder/hiring lead on LinkedIn using your tailored connection note below.',
                    style: TextStyle(fontSize: 11.5, color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            // Regular AI Summary Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Colors.amber, size: 15),
                      const SizedBox(width: 6),
                      Text(
                        'AI Summary',
                        style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    item.summary,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                  if (item.actionRequired.isNotEmpty && item.actionRequired != 'None') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.touch_app_rounded, size: 13, color: Colors.amber),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Action Required: ${item.actionRequired}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Email Body Preview (if available)
          if (item.bodyPreview.isNotEmpty) ...[
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: const Text(
                  'View Email Snippet',
                  style: TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.w600),
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black26 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(
                      item.bodyPreview,
                      style: TextStyle(fontSize: 12, height: 1.4, color: isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Action Buttons
          Row(
            children: [
              if (item.isBounced) ...[
                if (item.linkedinUrl != null && item.linkedinUrl!.isNotEmpty)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _handleConnectLinkedIn(item),
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                      label: const Text('Connect on LinkedIn Instead 🔗'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0077B5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ] else ...[
                if (item.recipientEmail.isNotEmpty)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final mailtoUri = Uri(
                          scheme: 'mailto',
                          path: item.recipientEmail,
                          queryParameters: {
                            'subject': item.subject.startsWith('Re:') ? item.subject : 'Re: ${item.subject}',
                          },
                        );
                        await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.reply_rounded, size: 16),
                      label: const Text('Reply in Email'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0077B5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                if (item.linkedinUrl != null && item.linkedinUrl!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final uri = Uri.tryParse(item.linkedinUrl!);
                        if (uri != null) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: const Icon(Icons.person_rounded, size: 16),
                      label: const Text('Open LinkedIn'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class UnifiedReplyItem {
  final String id;
  final bool isStartupLead;
  final String companyName;
  final String roleOrTitle;
  final String recipientEmail;
  final String senderNameOrEmail;
  final String subject;
  final String responseType;
  final String summary;
  final String bodyPreview;
  final String actionRequired;
  final DateTime receivedAt;
  final String? linkedinUrl;
  final String? connectionNote;
  final bool isDismissed;
  final bool isBounced;

  UnifiedReplyItem({
    required this.id,
    required this.isStartupLead,
    required this.companyName,
    required this.roleOrTitle,
    required this.recipientEmail,
    required this.senderNameOrEmail,
    required this.subject,
    required this.responseType,
    required this.summary,
    required this.bodyPreview,
    required this.actionRequired,
    required this.receivedAt,
    this.linkedinUrl,
    this.connectionNote,
    this.isDismissed = false,
    this.isBounced = false,
  });
}
