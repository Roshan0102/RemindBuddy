import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/remote_company.dart';

class CompanyMatchResult {
  final RemoteCompany company;
  final int score;
  final List<String> matchedSkills;

  const CompanyMatchResult({
    required this.company,
    required this.score,
    required this.matchedSkills,
  });
}

class RemoteTechDirectoryService {
  static final RemoteTechDirectoryService _instance =
      RemoteTechDirectoryService._internal();
  factory RemoteTechDirectoryService() => _instance;
  RemoteTechDirectoryService._internal();

  List<RemoteCompany>? _cachedCompanies;

  /// Loads the verified remote companies dataset from assets.
  Future<List<RemoteCompany>> loadCompanies() async {
    if (_cachedCompanies != null && _cachedCompanies!.isNotEmpty) {
      return _cachedCompanies!;
    }

    try {
      final jsonString =
          await rootBundle.loadString('assets/data/remote_companies.json');
      final List<dynamic> list = jsonDecode(jsonString) as List<dynamic>;
      _cachedCompanies = list
          .map((item) => RemoteCompany.fromJson(item as Map<String, dynamic>))
          .toList();
      return _cachedCompanies!;
    } catch (e) {
      return [];
    }
  }

  /// Calculates a match score (0 - 100) between user skills/roles and company tech stack.
  CompanyMatchResult computeMatch(
    RemoteCompany company,
    List<String> userSkills,
  ) {
    if (userSkills.isEmpty) {
      return CompanyMatchResult(
        company: company,
        score: 60, // Baseline neutral score
        matchedSkills: const [],
      );
    }

    final normalizedUserSkills = userSkills
        .map((s) => s.toLowerCase().trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final matched = <String>[];
    for (final tech in company.technologies) {
      final t = tech.toLowerCase().trim();
      final hasMatch = normalizedUserSkills.any((skill) =>
          skill == t ||
          skill.contains(t) ||
          t.contains(skill) ||
          _areRelatedTechs(skill, t));
      if (hasMatch) {
        matched.add(tech);
      }
    }

    // Also check blurb for skill mentions
    final blurbLower = company.blurb.toLowerCase();
    for (final skill in normalizedUserSkills) {
      if (skill.length > 2 &&
          blurbLower.contains(skill) &&
          !matched.any((m) => m.toLowerCase() == skill)) {
        matched.add(skill);
      }
    }

    int score = 40;
    if (matched.isNotEmpty) {
      score = (40 + (matched.length * 15)).clamp(40, 98);
    } else if (company.technologies.isEmpty) {
      score = 50;
    }

    return CompanyMatchResult(
      company: company,
      score: score,
      matchedSkills: matched,
    );
  }

  bool _areRelatedTechs(String a, String b) {
    const synonyms = {
      'aws': ['cloud', 'devops', 'infrastructure'],
      'gcp': ['cloud', 'devops', 'infrastructure'],
      'azure': ['cloud', 'devops', 'infrastructure'],
      'kubernetes': ['devops', 'docker', 'infrastructure', 'k8s'],
      'docker': ['devops', 'containers', 'infrastructure'],
      'react': ['frontend', 'javascript', 'typescript', 'web'],
      'vue': ['frontend', 'javascript', 'typescript', 'web'],
      'flutter': ['mobile', 'dart', 'cross-platform', 'ios', 'android'],
      'python': ['backend', 'machine learning', 'data', 'django', 'fastapi'],
      'golang': ['backend', 'go', 'microservices', 'infrastructure'],
      'node': ['backend', 'javascript', 'typescript', 'express'],
      'nodejs': ['backend', 'javascript', 'typescript', 'express'],
    };

    for (final entry in synonyms.entries) {
      final key = entry.key;
      final syns = entry.value;
      if ((a == key && syns.contains(b)) || (b == key && syns.contains(a))) {
        return true;
      }
    }
    return false;
  }

  /// Filters and sorts remote companies according to user criteria.
  List<CompanyMatchResult> filterCompanies({
    required List<RemoteCompany> companies,
    required List<String> userSkills,
    String query = '',
    String selectedRegion = 'all',
    String selectedPolicy = 'all',
    String selectedSize = 'all',
    String sortBy = 'match', // 'match', 'name', 'size'
  }) {
    final cleanQuery = query.toLowerCase().trim();

    final filtered = companies.where((c) {
      if (selectedRegion != 'all' && c.region != selectedRegion) {
        return false;
      }
      if (selectedPolicy != 'all' && c.remotePolicy != selectedPolicy) {
        return false;
      }
      if (selectedSize != 'all' && c.companySize != selectedSize) {
        return false;
      }
      if (cleanQuery.isNotEmpty) {
        final inTitle = c.title.toLowerCase().contains(cleanQuery);
        final inBlurb = c.blurb.toLowerCase().contains(cleanQuery);
        final inTech = c.technologies
            .any((t) => t.toLowerCase().contains(cleanQuery));
        final inRegion = c.region.toLowerCase().contains(cleanQuery);
        if (!inTitle && !inBlurb && !inTech && !inRegion) {
          return false;
        }
      }
      return true;
    }).map((c) => computeMatch(c, userSkills)).toList();

    if (sortBy == 'match') {
      filtered.sort((a, b) {
        final scoreComp = b.score.compareTo(a.score);
        if (scoreComp != 0) return scoreComp;
        return a.company.title.toLowerCase().compareTo(b.company.title.toLowerCase());
      });
    } else if (sortBy == 'name') {
      filtered.sort((a, b) =>
          a.company.title.toLowerCase().compareTo(b.company.title.toLowerCase()));
    } else if (sortBy == 'size') {
      final sizeWeights = {'large': 3, 'medium': 2, 'small': 1};
      filtered.sort((a, b) {
        final wa = sizeWeights[a.company.companySize.toLowerCase()] ?? 0;
        final wb = sizeWeights[b.company.companySize.toLowerCase()] ?? 0;
        return wb.compareTo(wa);
      });
    }

    return filtered;
  }

  /// Generates a personalized cold email pitch tailored for this company and applicant.
  String generatePitch({
    required RemoteCompany company,
    required String applicantName,
    required String applicantRole,
    required List<String> skills,
    required List<String> matchedSkills,
  }) {
    final name = applicantName.isNotEmpty ? applicantName : 'Applicant';
    final role = applicantRole.isNotEmpty ? applicantRole : 'Software Engineer';
    final companyName = company.title;
    final relevantSkills = matchedSkills.isNotEmpty
        ? matchedSkills.take(3).join(', ')
        : (skills.isNotEmpty ? skills.take(3).join(', ') : 'modern tech stacks');

    final techLine = company.technologies.isNotEmpty
        ? "I noticed $companyName's work with ${company.technologies.take(3).join(', ')}, which closely matches my core focus in $relevantSkills."
        : "I've been following $companyName's remote-first team and admire your mission in building innovative distributed products.";

    return '''
Subject: Exploring opportunities at $companyName – $name ($role)

Hi $companyName Team,

I hope you are having a productive week.

$techLine

As an experienced $role, I specialize in delivering high-impact solutions, optimizing workflows, and thriving in autonomous, distributed environments. Given $companyName's commitment to ${company.formattedRemotePolicy.toLowerCase()} culture, I wanted to reach out directly to express my keen interest in contributing to your engineering and product goals.

Key highlights I bring to the table:
• Proven expertise with $relevantSkills
• Strong bias for asynchronous collaboration, clear documentation, and ownership
• Track record of shipping reliable, scalable systems in distributed setups

I have reviewed your careers page and would love to connect for 10-15 minutes to learn more about your upcoming roadmap and share how my background aligns with your team's needs.

Looking forward to the possibility of collaborating!

Best regards,
$name
$role
'''.trim();
  }
}
