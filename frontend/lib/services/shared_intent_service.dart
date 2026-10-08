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

      // Proceed with background AI analysis silently (intermediate notification removed to avoid notification spam)
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
          final recentApp = await jobService.findRecentApplication(
            recipientEmail: job.recipientEmail,
            companyName: job.companyName,
            jobTitle: job.jobTitle,
            withinDays: 30,
          );
          if (recentApp != null) {
            await NotificationService().showNotification(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: 'ℹ️ Already Applied: ${job.jobTitle}',
              body: 'You applied to ${job.companyName} on ${_formatDate(recentApp.appliedAt)}. Re-applying allowed after 30 days.',
              channelId: 'job_assistant_share_channel',
              channelName: 'Job Assistant Auto-Apply',
              payload: 'JOB_APPLICATION',
            );
            continue;
          }

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
          final recentApp = await jobService.findRecentApplication(
            recipientEmail: job.recipientEmail,
            companyName: job.companyName,
            jobTitle: job.jobTitle,
            sourceUrl: sourceUrl,
            withinDays: 30,
          );
          if (recentApp != null) {
            await NotificationService().showNotification(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: 'ℹ️ Already Applied: ${job.jobTitle}',
              body: 'You applied to ${job.companyName} on ${_formatDate(recentApp.appliedAt)}. Re-applying allowed after 30 days.',
              channelId: 'job_assistant_share_channel',
              channelName: 'Job Assistant Auto-Apply',
              payload: 'JOB_APPLICATION',
            );
            return true;
          }

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

  Future<String> _expandUrl(String url) async {
    try {
      final client = http.Client();
      final uri = Uri.parse(url);
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      final streamedResponse =
          await client.send(request).timeout(const Duration(seconds: 8));
      if (streamedResponse.isRedirect ||
          (streamedResponse.statusCode >= 300 &&
              streamedResponse.statusCode < 400)) {
        final location = streamedResponse.headers['location'];
        if (location != null && location.isNotEmpty) {
          debugPrint('[SharedIntentService] Expanded short URL $url -> $location');
          return location;
        }
      }
    } catch (e) {
      debugPrint('[SharedIntentService] Error expanding URL $url: $e');
    }
    return url;
  }

  String _cleanPostUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.contains('linkedin.com')) {
        // Strip tracking query parameters (highlightedUpdateUrn, utm_source, rcm, etc.)
        return Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.hasPort ? uri.port : null,
          path: uri.path,
        ).toString();
      }
    } catch (_) {}
    return url;
  }

  Future<void> _processSharedUrl(String url, {required String originalText}) async {
    final jobService = JobAssistantService();

    // 1. Expand shortened lnkd.in links to full destination URL and clean tracking query parameters
    final rawExpandedUrl = (url.contains('lnkd.in') || url.length < 35) ? await _expandUrl(url) : url;
    final expandedUrl = _cleanPostUrl(rawExpandedUrl);
    debugPrint('[SharedIntentService] Processing URL: $expandedUrl (original: $url)');

    final isLinkedIn = url.toLowerCase().contains('linkedin') ||
        url.toLowerCase().contains('lnkd.in') ||
        expandedUrl.toLowerCase().contains('linkedin') ||
        expandedUrl.toLowerCase().contains('lnkd.in');

    // Proceed silently in background (intermediate progress notification removed to prevent spam)
    // 2. Try public fetch of the URL with desktop headers to capture OpenGraph flyer image and text
    bool successfullyParsed = false;
    try {
      final response = await http.get(
        Uri.parse(expandedUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 12));

      final html = response.body;
      final effectiveUrl = response.request?.url.toString() ?? expandedUrl;

      // Extract OpenGraph tags
      final ogImageUrl = _extractMetaTag(html, 'og:image') ?? _extractMetaTag(html, 'twitter:image');
      final ogDescription = _extractMetaTag(html, 'og:description') ?? _extractMetaTag(html, 'description');

      final hasSubstantiveDescription = ogDescription != null &&
          ogDescription.trim().length > 25 &&
          !ogDescription.contains('500 million+ members') &&
          !ogDescription.contains('Manage your professional identity') &&
          !ogDescription.toLowerCase().contains('sign in to linkedin to view') &&
          !ogDescription.toLowerCase().contains('join linkedin to view');

      final hasPostFlyerImage = ogImageUrl != null &&
          ogImageUrl.isNotEmpty &&
          !ogImageUrl.contains('profile') &&
          !ogImageUrl.contains('ghost') &&
          !ogImageUrl.contains('static.licdn.com/aero-v1') &&
          !ogImageUrl.contains('favicon');

      // True authwall only if no substantive content was returned and URL or status indicates a hard wall
      final isTrueAuthWall = (!hasSubstantiveDescription && !hasPostFlyerImage) && (
          effectiveUrl.contains('/authwall') ||
          effectiveUrl.contains('/checkpoint') ||
          effectiveUrl.contains('/signup') ||
          response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 404
      );

      if (!isTrueAuthWall && response.statusCode == 200 && (hasPostFlyerImage || hasSubstantiveDescription)) {
        if (hasPostFlyerImage) {
          final imgUrl = ogImageUrl;
          final imgRes = await http.get(
            Uri.parse(imgUrl),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
          ).timeout(const Duration(seconds: 10));
          if (imgRes.statusCode == 200 && imgRes.bodyBytes.isNotEmpty) {
            final base64Img = base64Encode(imgRes.bodyBytes);
            final parsed = await jobService.parseJobPostersWithAI(
              [base64Img],
              'single_job',
              jobText: ogDescription,
              customPrompt: 'Extract hiring post details, company, role, recruiter email, and write a high-converting application.',
            );
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
                sourcePlatform: isLinkedIn ? 'LinkedIn Share' : 'Shared Link',
                source: isLinkedIn ? 'linkedin_share' : 'shared_link',
                sourceUrl: expandedUrl,
                posterImageUrls: [imgUrl],
                postExcerpt: ogDescription != null && ogDescription.length > 200 ? '${ogDescription.substring(0, 200)}...' : ogDescription,
                errorMessage: rawJob.recipientEmail.trim().isEmpty ? 'No direct recruiter email found in flyer. Saved in History drafts.' : null,
              );

              if (job.recipientEmail.isNotEmpty) {
                final recentApp = await jobService.findRecentApplication(
                  recipientEmail: job.recipientEmail,
                  companyName: job.companyName,
                  jobTitle: job.jobTitle,
                  sourceUrl: expandedUrl,
                  withinDays: 30,
                );
                if (recentApp != null) {
                  await NotificationService().showNotification(
                    id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    title: 'ℹ️ Already Applied: ${job.jobTitle}',
                    body: 'You applied to ${job.companyName} on ${_formatDate(recentApp.appliedAt)}. Re-applying allowed after 30 days.',
                    channelId: 'job_assistant_share_channel',
                    channelName: 'Job Assistant Auto-Apply',
                    payload: 'JOB_APPLICATION',
                  );
                } else {
                  await jobService.sendJobApplicationEmail(job);
                  await NotificationService().showNotification(
                    id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    title: '🎯 1-Click Applied: ${job.jobTitle}',
                    body: 'Applied to ${job.companyName} (${job.recipientEmail}) from shared post flyer.',
                    channelId: 'job_assistant_share_channel',
                    channelName: 'Job Assistant Auto-Apply',
                    payload: 'JOB_APPLICATION',
                  );
                }
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

        if (!successfullyParsed && hasSubstantiveDescription) {
          final descText = ogDescription;
          final parsed = await jobService.parseJobTextWithAI(
            descText,
            customPrompt: 'Extract hiring post details, company, role, recruiter email, and write a high-converting application.',
          );
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
              sourcePlatform: isLinkedIn ? 'LinkedIn Share' : 'Shared Text',
              source: isLinkedIn ? 'linkedin_share' : 'shared_text',
              sourceUrl: expandedUrl,
              postExcerpt: descText.length > 200 ? '${descText.substring(0, 200)}...' : descText,
              errorMessage: rawJob.recipientEmail.trim().isEmpty ? 'No direct recruiter email found in post. Saved in History drafts.' : null,
            );

            if (job.recipientEmail.isNotEmpty) {
              final recentApp = await jobService.findRecentApplication(
                recipientEmail: job.recipientEmail,
                companyName: job.companyName,
                jobTitle: job.jobTitle,
                sourceUrl: expandedUrl,
                withinDays: 30,
              );
              if (recentApp != null) {
                await NotificationService().showNotification(
                  id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  title: 'ℹ️ Already Applied: ${job.jobTitle}',
                  body: 'You applied to ${job.companyName} on ${_formatDate(recentApp.appliedAt)}. Re-applying allowed after 30 days.',
                  channelId: 'job_assistant_share_channel',
                  channelName: 'Job Assistant Auto-Apply',
                  payload: 'JOB_APPLICATION',
                );
              } else {
                await jobService.sendJobApplicationEmail(job);
                await NotificationService().showNotification(
                  id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  title: '🎯 1-Click Applied: ${job.jobTitle}',
                  body: 'Applied to ${job.companyName} (${job.recipientEmail}) from shared post text.',
                  channelId: 'job_assistant_share_channel',
                  channelName: 'Job Assistant Auto-Apply',
                  payload: 'JOB_APPLICATION',
                );
              }
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
    } catch (e) {
      debugPrint('[SharedIntentService] Public URL fetch notice: $e');
    }

    // 3. If unauthenticated fetch was blocked by login wall, attempt Apify residential post scraper if configured
    if (!successfullyParsed && isLinkedIn) {
      final apifySuccess = await _tryScrapeWithApify(expandedUrl);
      if (apifySuccess) return;
    }

    // 4. Fallback: Save in Unified Apply History with the exact post link and notify user
    if (!successfullyParsed) {
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
        sourceUrl: expandedUrl,
        errorMessage: isLinkedIn
            ? 'This post is behind LinkedIn\'s sign-in wall. Saved in History drafts.'
            : 'Could not automatically extract job details from link. Saved in History drafts.',
      );

      await jobService.saveJobApplication(failedApp);

      await NotificationService().showNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: isLinkedIn ? '📋 Post Link Saved in Drafts' : '⚠️ Link Saved in Drafts',
        body: isLinkedIn
            ? 'Post link saved in History drafts. You can review or apply anytime!'
            : 'Link saved in History drafts.',
        channelId: 'job_assistant_share_channel',
        channelName: 'Job Assistant Auto-Apply',
        payload: 'OPEN_URL|$expandedUrl',
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
          final recentApp = await jobService.findRecentApplication(
            recipientEmail: job.recipientEmail,
            companyName: job.companyName,
            jobTitle: job.jobTitle,
            withinDays: 30,
          );
          if (recentApp != null) {
            await NotificationService().showNotification(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: 'ℹ️ Already Applied: ${job.jobTitle}',
              body: 'You applied to ${job.companyName} on ${_formatDate(recentApp.appliedAt)}. Re-applying allowed after 30 days.',
              channelId: 'job_assistant_share_channel',
              channelName: 'Job Assistant Auto-Apply',
              payload: 'JOB_APPLICATION',
            );
          } else {
            await jobService.sendJobApplicationEmail(job);
            await NotificationService().showNotification(
              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              title: '🎯 1-Click Applied: ${job.jobTitle}',
              body: 'Applied to ${job.companyName} (${job.recipientEmail}) from shared text.',
              channelId: 'job_assistant_share_channel',
              channelName: 'Job Assistant Auto-Apply',
              payload: 'JOB_APPLICATION',
            );
          }
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

      // Multi-Token Failover: Try Token 1 -> Token 2 -> Token 3 (silently without intermediate progress notifications)
      for (int i = 0; i < apifyTokens.length; i++) {
        final token = apifyTokens[i];
        final maskedToken = token.length > 8 ? '${token.substring(0, 4)}...${token.substring(token.length - 4)}' : '***';
        debugPrint('[SharedIntentService] Trying Apify token #${i + 1} ($maskedToken)...');

        final cleanScrapeUrl = _cleanPostUrl(url);
        try {
          http.Response response = await http.post(
            Uri.parse('https://api.apify.com/v2/acts/thirdwatch~linkedin-post-scraper/run-sync-get-dataset-items?token=${Uri.encodeComponent(token)}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'postUrls': [cleanScrapeUrl],
              'maxPosts': 1,
            }),
          ).timeout(const Duration(seconds: 40));

          if ((response.statusCode != 200 && response.statusCode != 201) || response.body.trim() == '[]') {
            response = await http.post(
              Uri.parse('https://api.apify.com/v2/acts/supreme_coder~linkedin-post/run-sync-get-dataset-items?token=${Uri.encodeComponent(token)}'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'urls': [cleanScrapeUrl],
                'postUrls': [cleanScrapeUrl],
                'deepScrape': true,
              }),
            ).timeout(const Duration(seconds: 40));
          }

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
                    final recentApp = await jobService.findRecentApplication(
                      recipientEmail: job.recipientEmail,
                      companyName: job.companyName,
                      jobTitle: job.jobTitle,
                      sourceUrl: url,
                      withinDays: 30,
                    );
                    if (recentApp != null) {
                      await NotificationService().showNotification(
                        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                        title: 'ℹ️ Already Applied: ${job.jobTitle}',
                        body: 'You applied to ${job.companyName} on ${_formatDate(recentApp.appliedAt)}. Re-applying allowed after 30 days.',
                        channelId: 'job_assistant_share_channel',
                        channelName: 'Job Assistant Auto-Apply',
                        payload: 'JOB_APPLICATION',
                      );
                    } else {
                      await jobService.sendJobApplicationEmail(job);
                      await NotificationService().showNotification(
                        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                        title: '🎯 1-Click Applied: ${job.jobTitle}',
                        body: 'Applied to ${job.companyName} (${job.recipientEmail}) via Apify post extraction.',
                        channelId: 'job_assistant_share_channel',
                        channelName: 'Job Assistant Auto-Apply',
                        payload: 'JOB_APPLICATION',
                      );
                    }
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

  String? _unescapeHtml(String? text) {
    if (text == null) return null;
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
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
        return _unescapeHtml(match.group(1));
      }
    }
    return null;
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final m = (dt.month >= 1 && dt.month <= 12) ? months[dt.month - 1] : '';
    return '${dt.day} $m ${dt.year}';
  }
}
