import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
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
  String _activeFilter = 'all'; // 'all', 'interview_invite', 'founder_chat', 'assessment', 'hr_query'

  Future<void> _checkRepliesNow() async {
    setState(() {
      _isCheckingReplies = true;
    });

    try {
      final res = await _service.checkJobRepliesNow();
      final repliesFound = res['repliesFound'] ?? 0;
      final checked = res['checked'] ?? 0;

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
        title: Text(
          'Recruiter & Founder Replies 📬',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
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
        stream: _service.getJobApplicationsStream(),
        builder: (context, appSnap) {
          return StreamBuilder<List<NetworkingLead>>(
            stream: _service.getNetworkingLeadsStream(),
            builder: (context, leadSnap) {
              if (appSnap.connectionState == ConnectionState.waiting &&
                  leadSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allApps = appSnap.data ?? [];
              final allLeads = leadSnap.data ?? [];

              // Filter to items that have received replies
              final appReplies = allApps.where((a) => a.status == 'reply_received').toList();
              final leadReplies = allLeads.where((l) => l.status == 'replied').toList();

              // Unified reply list
              final List<UnifiedReplyItem> unifiedReplies = [];

              for (final a in appReplies) {
                unifiedReplies.add(UnifiedReplyItem(
                  id: a.id,
                  isStartupLead: false,
                  companyName: a.companyName,
                  roleOrTitle: a.jobTitle,
                  recipientEmail: a.recipientEmail,
                  senderNameOrEmail: a.replySender ?? a.recipientEmail,
                  subject: a.replySubject ?? a.generatedSubject,
                  responseType: a.responseType ?? 'hr_query',
                  summary: a.replySnippet ?? 'Recruiter replied to your application.',
                  bodyPreview: a.replyBodyPreview ?? '',
                  actionRequired: a.actionRequired ?? 'Check your email',
                  receivedAt: a.replyReceivedAt ?? a.appliedAt,
                ));
              }

              for (final l in leadReplies) {
                unifiedReplies.add(UnifiedReplyItem(
                  id: l.id,
                  isStartupLead: true,
                  companyName: l.companyName,
                  roleOrTitle: l.currentRole,
                  recipientEmail: l.email ?? '',
                  senderNameOrEmail: l.replySender ?? l.name,
                  subject: l.replySubject ?? l.emailSubject ?? 'Re: Pitch',
                  responseType: l.responseType ?? 'founder_chat',
                  summary: l.replySnippet ?? 'Founder replied to your pitch.',
                  bodyPreview: l.replyBodyPreview ?? '',
                  actionRequired: l.actionRequired ?? 'Reply via email',
                  receivedAt: l.replyReceivedAt ?? l.discoveredAt,
                  linkedinUrl: l.linkedinUrl,
                ));
              }

              // Sort by received time descending
              unifiedReplies.sort((x, y) => y.receivedAt.compareTo(x.receivedAt));

              // Filter by responseType
              var filteredReplies = unifiedReplies;
              if (_activeFilter != 'all') {
                filteredReplies = unifiedReplies.where((r) => r.responseType == _activeFilter).toList();
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
                      ],
                    ),
                  ),
                );
              }

              final interviewCount = unifiedReplies.where((r) => r.responseType == 'interview_invite').length;
              final founderCount = unifiedReplies.where((r) => r.responseType == 'founder_chat' || r.isStartupLead).length;
              final assessmentCount = unifiedReplies.where((r) => r.responseType == 'assessment').length;

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
                                  '${unifiedReplies.length} Total Verified Replies Received!',
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : const Color(0xFF14532D),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$interviewCount Interview Invites • $founderCount Founder Responses • $assessmentCount Assessments',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? Colors.white70 : Colors.green.shade900,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
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

                    // Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('all', 'All Replies (${unifiedReplies.length})'),
                          const SizedBox(width: 8),
                          _buildFilterChip('interview_invite', 'Interview Invites 🎯 ($interviewCount)'),
                          const SizedBox(width: 8),
                          _buildFilterChip('founder_chat', 'Founder Chats 🚀 ($founderCount)'),
                          const SizedBox(width: 8),
                          _buildFilterChip('assessment', 'Assessments 📝 ($assessmentCount)'),
                          const SizedBox(width: 8),
                          _buildFilterChip('hr_query', 'HR Messages 💬'),
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

    final timeStr = DateFormat('dd MMM yyyy, h:mm a').format(item.receivedAt);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.3),
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
          // Top Row: Source Pill, Badge, Time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

          // AI Summary Box
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
  });
}
