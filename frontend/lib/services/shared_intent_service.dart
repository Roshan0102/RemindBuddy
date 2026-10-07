import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/job_application.dart';
import 'job_assistant_service.dart';
import 'notification_service.dart';

class SharedIntentService {
  static final SharedIntentService _instance = SharedIntentService._internal();
  factory SharedIntentService() => _instance;
  SharedIntentService._internal();

  static const MethodChannel _methodChannel = MethodChannel('com.remindbuddy/share_receiver');
  static const EventChannel _eventChannel = EventChannel('com.remindbuddy/shared_data_stream');

  StreamSubscription? _streamSub;
  bool _isInitialized = false;
  String _lastProcessedFingerprint = '';
  DateTime _lastProcessedTime = DateTime.fromMillisecondsSinceEpoch(0);

  void init() {
    if (_isInitialized || kIsWeb) return;
    _isInitialized = true;

    // 1. Check for initial share data when app was launched via share sheet
    _checkInitialSharedData();

    // 2. Listen for runtime shares while app is open / in background
    _streamSub = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          _handleIncomingShare(Map<String, dynamic>.from(event));
        }
      },
      onError: (err) {
        debugPrint('[SharedIntentService] Error on shared_data_stream: $err');
      },
    );
  }

  void dispose() {
    _streamSub?.cancel();
    _isInitialized = false;
  }

  Future<void> _checkInitialSharedData() async {
    try {
      final res = await _methodChannel.invokeMethod('getInitialSharedData');
      if (res != null && res is Map) {
        await _handleIncomingShare(Map<String, dynamic>.from(res));
      }
    } catch (e) {
      debugPrint('[SharedIntentService] Error checking initial shared data: $e');
    }
  }

  Future<void> _handleIncomingShare(Map<String, dynamic> data) async {
    final type = data['type']?.toString() ?? '';
    debugPrint('[SharedIntentService] Received shared intent of type: $type');

    // Debounce to avoid duplicate processing within 3 seconds
    final fingerprint = '$type:${data['text'] ?? ''}:${data['imagePaths'] ?? ''}';
    final now = DateTime.now();
    if (fingerprint == _lastProcessedFingerprint && now.difference(_lastProcessedTime).inSeconds < 3) {
      debugPrint('[SharedIntentService] Duplicate intent ignored: $fingerprint');
      return;
    }
    _lastProcessedFingerprint = fingerprint;
    _lastProcessedTime = now;

    if (type == 'image') {
      final paths = List<String>.from(data['imagePaths'] ?? []);
      if (paths.isNotEmpty) {
        await _processSharedImages(paths);
      }
    } else if (type == 'text') {
      final text = data['text']?.toString() ?? '';
      if (text.trim().isNotEmpty) {
        await _processSharedText(text.trim());
      }
    }
  }

  // ============================================================================
  // PROCESS SHARED SCREENSHOTS / IMAGES
  // ============================================================================

  Future<void> _processSharedImages(List<String> filePaths) async {
    try {
      final List<String> base64Images = [];
      for (final p in filePaths) {
        final f = File(p);
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          base64Images.add(base64Encode(bytes));
        }
      }

      if (base64Images.isEmpty) {
        debugPrint('[SharedIntentService] No valid image bytes found in paths: $filePaths');
        return;
      }

      // Notify user that analysis started in background
      await NotificationService().showNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: '📸 Analyzing Job Poster with Gemini AI...',
        body: 'Extracting role, recruiter email, and preparing application in background.',
        channelId: 'job_assistant_share_channel',
        channelName: 'Job Assistant Auto-Apply',
        payload: 'JOB_APPLICATION',
      );

      final jobService = JobAssistantService();
      final mode = base64Images.length > 1 ? 'multiple_jobs' : 'single_job';
      final List<JobApplication> parsedJobs = await jobService.parseJobPostersWithAI(
        base64Images,
        mode,
        customPrompt: 'Extract hiring post details, company, role, recruiter email, and write a high-converting application.',
      );

      if (parsedJobs.isEmpty) {
        await NotificationService().showNotification(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: '⚠️ Gemini Could Not Analyze Poster',
          body: 'No job openings detected in the shared screenshot.',
          channelId: 'job_assistant_share_channel',
          channelName: 'Job Assistant Auto-Apply',
          payload: 'JOB_APPLICATION',
        );
        return;
      }

      for (final rawJob in parsedJobs) {
        final job = JobApplication(
          id: rawJob.id,
          jobTitle: rawJob.jobTitle,
          companyName: rawJob.companyName,
          recipientEmail: rawJob.recipientEmail,
          extractedSkills: rawJob.extractedSkills,
          generatedSubject: rawJob.generatedSubject,
          generatedCoverLetter: rawJob.generatedCoverLetter,
          status: rawJob.recipientEmail.trim().isNotEmpty ? 'extracted' : 'needs_review',
          appliedAt: DateTime.now(),
          sourcePlatform: 'Shared Screenshot',
          source: 'shared_screenshot',
          errorMessage: rawJob.recipientEmail.trim().isNotEmpty
              ? null
              : 'No recruiter email found in screenshot flyer. Saved in History drafts.',
        );

        if (job.recipientEmail.trim().isNotEmpty) {
          // Valid recipient email found -> auto-apply directly in background!
          try {
            await jobService.sendJobApplicationEmail(job);
            await NotificationService().showNotification(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: '🎯 1-Click Applied: ${job.jobTitle}',
              body: 'Sent tailored resume & application to ${job.companyName} (${job.recipientEmail}).',
              channelId: 'job_assistant_share_channel',
              channelName: 'Job Assistant Auto-Apply',
              payload: 'JOB_APPLICATION',
            );
          } catch (sendErr) {
            debugPrint('[SharedIntentService] Failed to auto-send email: $sendErr');
            // Save as draft in history with error message
            await jobService.saveJobApplication(JobApplication(
              id: job.id,
              jobTitle: job.jobTitle,
              companyName: job.companyName,
              recipientEmail: job.recipientEmail,
              extractedSkills: job.extractedSkills,
              generatedSubject: job.generatedSubject,
              generatedCoverLetter: job.generatedCoverLetter,
              status: 'needs_review',
              appliedAt: DateTime.now(),
              sourcePlatform: 'Shared Screenshot',
              source: 'shared_screenshot',
              errorMessage: 'Email send error: $sendErr. Saved in Drafts.',
            ));
            await NotificationService().showNotification(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: '⚠️ Could Not Send Email: ${job.jobTitle}',
              body: 'Extracted for ${job.companyName}, but email sending failed: $sendErr. Saved in Drafts.',
              channelId: 'job_assistant_share_channel',
              channelName: 'Job Assistant Auto-Apply',
              payload: 'JOB_APPLICATION',
            );
          }
        } else {
          // No direct email found (e.g. flyer instructs to apply on company website)
          await jobService.saveJobApplication(job);

          await NotificationService().showNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: '📋 Job Poster Analyzed: ${job.jobTitle}',
            body: 'Found for ${job.companyName}. No recruiter email detected in flyer — saved in History drafts.',
            channelId: 'job_assistant_share_channel',
            channelName: 'Job Assistant Auto-Apply',
            payload: 'JOB_APPLICATION',
          );
        }
      }
    } catch (e) {
      debugPrint('[SharedIntentService] Error processing shared image: $e');
      await NotificationService().showNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: '⚠️ Gemini Could Not Analyze Poster',
        body: 'Could not extract job from image: $e',
        channelId: 'job_assistant_share_channel',
        channelName: 'Job Assistant Auto-Apply',
        payload: 'JOB_APPLICATION',
      );
    }
  }

  // ============================================================================
  // PROCESS SHARED TEXT / LINK
  // ============================================================================

  Future<void> _processSharedText(String text) async {
    final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(text);
    if (urlMatch != null) {
      final url = urlMatch.group(0)!;
      final textWithoutUrl = text.replaceAll(url, '').trim();

      // If user shared a message with substantive job text + link (e.g. recruiter message)
      if (textWithoutUrl.length > 50 || (textWithoutUrl.contains('@') && !textWithoutUrl.contains('static.licdn.com'))) {
        debugPrint('[SharedIntentService] Found URL with substantial body text, analyzing text first...');
        final handledWithText = await _tryProcessJobText(text, sourceUrl: url);
        if (handledWithText) return;
      }

      await _processSharedUrl(url, originalText: text);
    } else {
      await _processSharedJobText(text);
    }
  }

  Future<bool> _tryProcessJobText(String text, {required String sourceUrl}) async {
    final jobService = JobAssistantService();
    try {
      final parsed = await jobService.parseJobTextWithAI(text);
      if (parsed.isNotEmpty) {
        final rawJob = parsed.first;
        final job = JobApplication(
          id: rawJob.id,
          jobTitle: rawJob.jobTitle,
          companyName: rawJob.companyName,
          recipientEmail: rawJob.recipientEmail,
          extractedSkills: rawJob.extractedSkills,
          generatedSubject: rawJob.generatedSubject,
          generatedCoverLetter: rawJob.generatedCoverLetter,
          status: rawJob.recipientEmail.trim().isNotEmpty ? 'sent' : 'needs_review',
          appliedAt: DateTime.now(),
          sourcePlatform: sourceUrl.contains('linkedin') ? 'LinkedIn Share' : 'Shared Text',
          source: sourceUrl.contains('linkedin') ? 'linkedin_share' : 'shared_text',
          sourceUrl: sourceUrl,
          errorMessage: rawJob.recipientEmail.trim().isEmpty ? 'No recruiter email found. Saved in Drafts.' : null,
        );

        if (job.recipientEmail.isNotEmpty) {
          await jobService.sendJobApplicationEmail(job);
          await NotificationService().showNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: '🎯 1-Click Applied: ${job.jobTitle}',
            body: 'Applied to ${job.companyName} (${job.recipientEmail}) from shared post text.',
            channelId: 'job_assistant_share_channel',
            channelName: 'Job Assistant Auto-Apply',
            payload: 'JOB_APPLICATION',
          );
        } else {
          await jobService.saveJobApplication(job);
          await NotificationService().showNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: '📋 Job Post Analyzed: ${job.jobTitle}',
            body: 'Found for ${job.companyName}. No recruiter email detected — saved in History drafts.',
            channelId: 'job_assistant_share_channel',
            channelName: 'Job Assistant Auto-Apply',
            payload: 'JOB_APPLICATION',
          );
        }
        return true;
      }
    } catch (e) {
      debugPrint('[SharedIntentService] Error in _tryProcessJobText: $e');
    }
    return false;
  }

  Future<void> _processSharedUrl(String url, {required String originalText}) async {
    final jobService = JobAssistantService();

    // Notify user that link processing has begun in background
    await NotificationService().showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: '🔗 Processing Shared Post...',
      body: 'Checking job details and recruiter contact in background.',
      channelId: 'job_assistant_share_channel',
      channelName: 'Job Assistant Auto-Apply',
      payload: 'JOB_APPLICATION',
    );

    // 1. Try public fetch of the URL to see if OpenGraph metadata or public HTML is available
    bool successfullyParsed = false;
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 8));

      final html = response.body;
      final effectiveUrl = response.request?.url.toString() ?? '';

      // Check if page redirected to LinkedIn login/join wall
      final isLoginWall = html.contains('p_registration-cold-join') ||
          html.contains('cold-join') ||
          html.contains('authwall') ||
          html.contains('Join LinkedIn') ||
          html.contains('Sign in to LinkedIn') ||
          effectiveUrl.contains('cold-join') ||
          effectiveUrl.contains('signup') ||
          response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 404;

      if (!isLoginWall && response.statusCode == 200) {
        // Check for og:image
        final ogImageUrl = _extractMetaTag(html, 'og:image') ?? _extractMetaTag(html, 'twitter:image');

        // Check for og:description
        final ogDescription = _extractMetaTag(html, 'og:description') ?? _extractMetaTag(html, 'description');

        if (ogImageUrl != null && ogImageUrl.isNotEmpty) {
          final imgUrl = ogImageUrl;
          if (!imgUrl.contains('profile') && !imgUrl.contains('ghost') && !imgUrl.contains('static.licdn.com/aero-v1') && !imgUrl.contains('favicon')) {
            final imgRes = await http.get(Uri.parse(imgUrl)).timeout(const Duration(seconds: 8));
            if (imgRes.statusCode == 200 && imgRes.bodyBytes.isNotEmpty) {
              final base64Img = base64Encode(imgRes.bodyBytes);
              final parsed = await jobService.parseJobPostersWithAI([base64Img], 'single_job');
              if (parsed.isNotEmpty) {
                successfullyParsed = true;
                final rawJob = parsed.first;
                final job = JobApplication(
                  id: rawJob.id,
                  jobTitle: rawJob.jobTitle,
                  companyName: rawJob.companyName,
                  recipientEmail: rawJob.recipientEmail,
                  extractedSkills: rawJob.extractedSkills,
                  generatedSubject: rawJob.generatedSubject,
                  generatedCoverLetter: rawJob.generatedCoverLetter,
                  status: rawJob.recipientEmail.trim().isNotEmpty ? 'sent' : 'needs_review',
                  appliedAt: DateTime.now(),
                  sourcePlatform: 'LinkedIn Share',
                  source: 'linkedin_share',
                  sourceUrl: url,
                  errorMessage: rawJob.recipientEmail.trim().isEmpty ? 'No recruiter email found in flyer. Saved in Drafts.' : null,
                );

                if (job.recipientEmail.isNotEmpty) {
                  await jobService.sendJobApplicationEmail(job);
                  await NotificationService().showNotification(
                    id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    title: '🎯 1-Click Applied: ${job.jobTitle}',
                    body: 'Applied to ${job.companyName} (${job.recipientEmail}) from shared post flyer.',
                    channelId: 'job_assistant_share_channel',
                    channelName: 'Job Assistant Auto-Apply',
                    payload: 'JOB_APPLICATION',
                  );
                } else {
                  await jobService.saveJobApplication(job);
                  await NotificationService().showNotification(
                    id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    title: '📋 Job Flyer Analyzed: ${job.jobTitle}',
                    body: 'Found for ${job.companyName}. No email detected in flyer — saved in Drafts.',
                    channelId: 'job_assistant_share_channel',
                    channelName: 'Job Assistant Auto-Apply',
                    payload: 'JOB_APPLICATION',
                  );
                }
              }
            }
          }
        }

        if (!successfullyParsed && ogDescription != null && ogDescription.isNotEmpty) {
          final descText = ogDescription;
          if (descText.trim().length > 30 && !descText.contains('500 million+ members') && !descText.contains('Manage your professional identity')) {
            final parsed = await jobService.parseJobTextWithAI(descText);
            if (parsed.isNotEmpty) {
              successfullyParsed = true;
              final rawJob = parsed.first;
              final job = JobApplication(
                id: rawJob.id,
                jobTitle: rawJob.jobTitle,
                companyName: rawJob.companyName,
                recipientEmail: rawJob.recipientEmail,
                extractedSkills: rawJob.extractedSkills,
                generatedSubject: rawJob.generatedSubject,
                generatedCoverLetter: rawJob.generatedCoverLetter,
                status: rawJob.recipientEmail.trim().isNotEmpty ? 'sent' : 'needs_review',
                appliedAt: DateTime.now(),
                sourcePlatform: 'LinkedIn Share',
                source: 'linkedin_share',
                sourceUrl: url,
                errorMessage: rawJob.recipientEmail.trim().isEmpty ? 'No email found in post. Saved in Drafts.' : null,
              );

              if (job.recipientEmail.isNotEmpty) {
                await jobService.sendJobApplicationEmail(job);
                await NotificationService().showNotification(
                  id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  title: '🎯 1-Click Applied: ${job.jobTitle}',
                  body: 'Applied to ${job.companyName} (${job.recipientEmail}) from shared post text.',
                  channelId: 'job_assistant_share_channel',
                  channelName: 'Job Assistant Auto-Apply',
                  payload: 'JOB_APPLICATION',
                );
              } else {
                await jobService.saveJobApplication(job);
                await NotificationService().showNotification(
                  id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  title: '📋 Job Post Analyzed: ${job.jobTitle}',
                  body: 'Found for ${job.companyName}. No email found — saved in Drafts.',
                  channelId: 'job_assistant_share_channel',
                  channelName: 'Job Assistant Auto-Apply',
                  payload: 'JOB_APPLICATION',
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[SharedIntentService] Public URL fetch notice: $e');
    }

    // 2. If unauthenticated fetch was blocked by login wall, attempt Apify residential post scraper if configured
    if (!successfullyParsed && url.toLowerCase().contains('linkedin')) {
      final apifySuccess = await _tryScrapeWithApify(url);
      if (apifySuccess) return;
    }

    // 3. If unauthenticated fetch failed or is behind login wall and Apify is unavailable:
    // Store in Unified Apply History with the exact post link and notify user to open & screenshot!
    if (!successfullyParsed) {
      final isLinkedIn = url.toLowerCase().contains('linkedin');
      final failedApp = JobApplication(
        id: '',
        jobTitle: isLinkedIn ? 'Shared LinkedIn Post' : 'Shared Job Link',
        companyName: isLinkedIn ? 'LinkedIn Post' : 'Job Portal',
        recipientEmail: '',
        extractedSkills: const [],
        generatedSubject: '',
        generatedCoverLetter: '',
        status: 'needs_review',
        appliedAt: DateTime.now(),
        sourcePlatform: isLinkedIn ? 'LinkedIn Share' : 'Shared Link',
        source: isLinkedIn ? 'linkedin_share' : 'shared_link',
        sourceUrl: url,
        errorMessage: isLinkedIn
            ? 'This post is behind LinkedIn\'s sign-in wall. Tap "View Original LinkedIn Post" below to open it in LinkedIn, snap a screenshot, and share the screenshot to SmartBuddy for 1-click apply!'
            : 'Could not automatically extract job details from link. Tap "View Job URL" below to inspect or share a screenshot!',
      );

      await jobService.saveJobApplication(failedApp);

      await NotificationService().showNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: isLinkedIn ? '⚠️ Shared Post Requires Screenshot' : '⚠️ Gemini Could Not Analyze Link',
        body: isLinkedIn
            ? 'Post requires login. Tap to open in LinkedIn, snap screenshot & share to auto-apply!'
            : 'Tap to open the link, snap screenshot & share to auto-apply!',
        channelId: 'job_assistant_share_channel',
        channelName: 'Job Assistant Auto-Apply',
        payload: 'OPEN_URL|$url',
      );
    }
  }

  Future<void> _processSharedJobText(String text) async {
    final jobService = JobAssistantService();
    try {
      final parsed = await jobService.parseJobTextWithAI(text);
      if (parsed.isNotEmpty) {
        final rawJob = parsed.first;
        final job = JobApplication(
          id: rawJob.id,
          jobTitle: rawJob.jobTitle,
          companyName: rawJob.companyName,
          recipientEmail: rawJob.recipientEmail,
          extractedSkills: rawJob.extractedSkills,
          generatedSubject: rawJob.generatedSubject,
          generatedCoverLetter: rawJob.generatedCoverLetter,
          status: rawJob.recipientEmail.trim().isNotEmpty ? 'sent' : 'needs_review',
          appliedAt: DateTime.now(),
          sourcePlatform: 'Shared Text',
          source: 'shared_text',
          errorMessage: rawJob.recipientEmail.trim().isEmpty ? 'No recruiter email found in text. Saved in Drafts.' : null,
        );

        if (job.recipientEmail.isNotEmpty) {
          await jobService.sendJobApplicationEmail(job);
          await NotificationService().showNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: '🎯 1-Click Applied: ${job.jobTitle}',
            body: 'Applied to ${job.companyName} (${job.recipientEmail}) from shared text.',
            channelId: 'job_assistant_share_channel',
            channelName: 'Job Assistant Auto-Apply',
            payload: 'JOB_APPLICATION',
          );
        } else {
          await jobService.saveJobApplication(job);
          await NotificationService().showNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: '📋 Job Opening Analyzed: ${job.jobTitle}',
            body: 'Found for ${job.companyName}. No email found — saved in Drafts.',
            channelId: 'job_assistant_share_channel',
            channelName: 'Job Assistant Auto-Apply',
            payload: 'JOB_APPLICATION',
          );
        }
      }
    } catch (e) {
      debugPrint('[SharedIntentService] Error parsing shared text: $e');
      await NotificationService().showNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: '⚠️ Gemini Could Not Analyze Text',
        body: 'Could not extract job opening from shared text: $e',
        channelId: 'job_assistant_share_channel',
        channelName: 'Job Assistant Auto-Apply',
        payload: 'JOB_APPLICATION',
      );
    }
  }

  Future<bool> _tryScrapeWithApify(String url) async {
    try {
      final jobService = JobAssistantService();
      final lSettings = await jobService.getLinkedInAutoApplySettings();
      
      // Collect all configured user tokens (Token 1 -> Token 2 -> Token 3)
      final List<String> apifyTokens = [];
      if (lSettings['apifyToken1'] != null && lSettings['apifyToken1'].toString().trim().isNotEmpty) {
        apifyTokens.add(lSettings['apifyToken1'].toString().trim());
      }
      if (lSettings['apifyToken2'] != null && lSettings['apifyToken2'].toString().trim().isNotEmpty) {
        apifyTokens.add(lSettings['apifyToken2'].toString().trim());
      }
      if (lSettings['apifyToken3'] != null && lSettings['apifyToken3'].toString().trim().isNotEmpty) {
        apifyTokens.add(lSettings['apifyToken3'].toString().trim());
      }
      final rawTokens = lSettings['apifyTokens'];
      if (rawTokens is List) {
        for (final t in rawTokens) {
          final s = t.toString().trim();
          if (s.isNotEmpty && !apifyTokens.contains(s)) {
            apifyTokens.add(s);
          }
        }
      }

      if (apifyTokens.isEmpty) {
        debugPrint('[SharedIntentService] No Apify tokens configured for user, skipping Apify.');
        return false;
      }

      // Notify user that Apify scraping has started
      await NotificationService().showNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: '🤖 Fetching LinkedIn Post via Apify...',
        body: 'Bypassing login wall using residential proxies. Please wait a moment...',
        channelId: 'job_assistant_share_channel',
        channelName: 'Job Assistant Auto-Apply',
        payload: 'JOB_APPLICATION',
      );

      // Multi-Token Failover: Try Token 1 -> Token 2 -> Token 3
      for (int i = 0; i < apifyTokens.length; i++) {
        final token = apifyTokens[i];
        final maskedToken = token.length > 8 ? '${token.substring(0, 4)}...${token.substring(token.length - 4)}' : '***';
        debugPrint('[SharedIntentService] Trying Apify token #${i + 1} ($maskedToken)...');

        try {
          final response = await http.post(
            Uri.parse('https://api.apify.com/v2/acts/supreme_coder~linkedin-post/run-sync-get-dataset-items?token=${Uri.encodeComponent(token)}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'urls': [url],
              'postUrls': [url],
            }),
          ).timeout(const Duration(seconds: 50));

          if (response.statusCode == 200 || response.statusCode == 201) {
            final List<dynamic> items = jsonDecode(response.body) as List<dynamic>? ?? [];
            if (items.isNotEmpty) {
              final item = Map<String, dynamic>.from(items.first);
              final postText = (item['text'] ?? item['content'] ?? item['postText'] ?? '').toString().trim();
              
              String authorName = '';
              if (item['authorName'] != null) {
                authorName = item['authorName'].toString().trim();
              } else if (item['author'] is Map) {
                final a = Map<String, dynamic>.from(item['author'] as Map);
                authorName = '${a['firstName'] ?? ''} ${a['lastName'] ?? ''}'.trim();
              }

              // Extract flyer image URLs attached to post
              final rawImages = item['images'] ?? item['media'] ?? item['attachments'];
              final List<String> imageUrls = [];
              if (rawImages is List) {
                for (final img in rawImages) {
                  if (img is String && img.startsWith('http')) {
                    imageUrls.add(img);
                  } else if (img is Map && img['url'] != null) {
                    imageUrls.add(img['url'].toString());
                  }
                }
              }

              // Download flyer images to base64 for Gemini Vision analysis
              final List<String> base64Images = [];
              for (final imgUrl in imageUrls.take(2)) {
                try {
                  final imgRes = await http.get(Uri.parse(imgUrl)).timeout(const Duration(seconds: 10));
                  if (imgRes.statusCode == 200 && imgRes.bodyBytes.isNotEmpty) {
                    base64Images.add(base64Encode(imgRes.bodyBytes));
                  }
                } catch (imgErr) {
                  debugPrint('[SharedIntentService] Failed to download Apify flyer image: $imgErr');
                }
              }

              if (postText.isNotEmpty || base64Images.isNotEmpty) {
                debugPrint('[SharedIntentService] Successfully retrieved post via Apify token #${i + 1}. Analyzing with Gemini AI...');
                
                final List<JobApplication> parsedJobs;
                if (base64Images.isNotEmpty) {
                  parsedJobs = await jobService.parseJobPostersWithAI(
                    base64Images,
                    'single_job',
                    jobText: postText,
                    customPrompt: 'Extract hiring post details, company, role, recruiter email, and write a high-converting application.',
                  );
                } else {
                  parsedJobs = await jobService.parseJobTextWithAI(postText);
                }

                if (parsedJobs.isNotEmpty) {
                  final rawJob = parsedJobs.first;
                  final job = JobApplication(
                    id: rawJob.id,
                    jobTitle: rawJob.jobTitle,
                    companyName: rawJob.companyName,
                    recipientEmail: rawJob.recipientEmail,
                    extractedSkills: rawJob.extractedSkills,
                    generatedSubject: rawJob.generatedSubject,
                    generatedCoverLetter: rawJob.generatedCoverLetter,
                    status: rawJob.recipientEmail.trim().isNotEmpty ? 'sent' : 'needs_review',
                    appliedAt: DateTime.now(),
                    sourcePlatform: 'LinkedIn Post (Apify Share)',
                    source: 'linkedin_post_apify',
                    sourceUrl: url,
                    authorName: authorName.isNotEmpty ? authorName : null,
                    postExcerpt: postText.length > 200 ? '${postText.substring(0, 200)}...' : postText,
                    errorMessage: rawJob.recipientEmail.trim().isEmpty ? 'No recruiter email found in post. Saved in Drafts.' : null,
                  );

                  if (job.recipientEmail.isNotEmpty) {
                    await jobService.sendJobApplicationEmail(job);
                    await NotificationService().showNotification(
                      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                      title: '🎯 1-Click Applied: ${job.jobTitle}',
                      body: 'Applied to ${job.companyName} (${job.recipientEmail}) via Apify post extraction.',
                      channelId: 'job_assistant_share_channel',
                      channelName: 'Job Assistant Auto-Apply',
                      payload: 'JOB_APPLICATION',
                    );
                  } else {
                    await jobService.saveJobApplication(job);
                    await NotificationService().showNotification(
                      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                      title: '📋 Post Extracted: ${job.jobTitle}',
                      body: 'Extracted for ${job.companyName}. No email found — saved in Drafts.',
                      channelId: 'job_assistant_share_channel',
                      channelName: 'Job Assistant Auto-Apply',
                      payload: 'JOB_APPLICATION',
                    );
                  }
                  return true;
                }
              }
            } else {
              debugPrint('[SharedIntentService] Apify token #${i + 1} returned empty items array.');
            }
          } else {
            debugPrint('[SharedIntentService] Apify token #${i + 1} returned HTTP ${response.statusCode}: ${response.body}. Moving to next token if available...');
          }
        } catch (tokenErr) {
          debugPrint('[SharedIntentService] Apify token #${i + 1} error: $tokenErr. Moving to next token if available...');
        }
      }
    } catch (e) {
      debugPrint('[SharedIntentService] Apify post scraping exception: $e');
    }
    return false;
  }

  String? _extractMetaTag(String html, String propertyName) {
    final patterns = [
      RegExp('<meta[^>]+property=["\']$propertyName["\'][^>]+content=["\']([^"\']+)["\']', caseSensitive: false),
      RegExp('<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']$propertyName["\']', caseSensitive: false),
      RegExp('<meta[^>]+name=["\']$propertyName["\'][^>]+content=["\']([^"\']+)["\']', caseSensitive: false),
      RegExp('<meta[^>]+content=["\']([^"\']+)["\'][^>]+name=["\']$propertyName["\']', caseSensitive: false),
    ];
    for (final p in patterns) {
      final match = p.firstMatch(html);
      if (match != null && match.group(1) != null) {
        return match.group(1)!.trim();
      }
    }
    return null;
  }
}
