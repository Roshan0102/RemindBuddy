import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/models/remote_company.dart';
import 'package:remindbuddy/services/remote_tech_directory_service.dart';

void main() {
  group('RemoteCompany Model Tests', () {
    test('Correctly parses from JSON and formats labels', () {
      final json = {
        'title': 'Automattic',
        'slug': 'automattic',
        'website': 'https://automattic.com',
        'careersUrl': 'https://automattic.com/work-with-us/',
        'region': 'worldwide',
        'remotePolicy': 'fully-remote',
        'companySize': 'large',
        'technologies': ['php', 'javascript', 'react', 'wordpress'],
        'blurb': 'We are the people behind WordPress.com, WooCommerce, and more.',
      };

      final company = RemoteCompany.fromJson(json);

      expect(company.title, 'Automattic');
      expect(company.slug, 'automattic');
      expect(company.website, 'https://automattic.com');
      expect(company.careersUrl, 'https://automattic.com/work-with-us/');
      expect(company.formattedRegion, 'Worldwide');
      expect(company.formattedRemotePolicy, 'Fully Remote');
      expect(company.formattedCompanySize, 'Large');
      expect(company.technologies.length, 4);

      final map = company.toJson();
      expect(map['title'], 'Automattic');
      expect(map['region'], 'worldwide');
    });

    test('Handles hyphenated regions and remote-friendly policies', () {
      final json = {
        'title': '15Five',
        'slug': '15five',
        'website': 'https://www.15five.com',
        'careersUrl': 'https://www.15five.com/careers',
        'region': 'americas-europe',
        'remotePolicy': 'remote-friendly',
        'companySize': 'medium',
        'technologies': ['devops', 'python'],
        'blurb': 'Performance management software.',
      };

      final company = RemoteCompany.fromJson(json);
      expect(company.formattedRegion, 'Americas / Europe');
      expect(company.formattedRemotePolicy, 'Remote Friendly');
      expect(company.formattedCompanySize, 'Medium');
    });
  });

  group('RemoteTechDirectoryService Tests', () {
    final service = RemoteTechDirectoryService();

    final testCompanies = [
      const RemoteCompany(
        title: 'GitLab',
        slug: 'gitlab',
        website: 'https://gitlab.com',
        careersUrl: 'https://about.gitlab.com/jobs/',
        region: 'worldwide',
        remotePolicy: 'fully-remote',
        companySize: 'large',
        technologies: ['ruby', 'golang', 'kubernetes', 'cloud', 'devops'],
        blurb: 'GitLab is an all-remote company that develops DevOps software.',
      ),
      const RemoteCompany(
        title: 'Buffer',
        slug: 'buffer',
        website: 'https://buffer.com',
        careersUrl: 'https://buffer.com/journey',
        region: 'worldwide',
        remotePolicy: 'fully-remote',
        companySize: 'small',
        technologies: ['react', 'node', 'javascript', 'docker'],
        blurb: 'Social media management tools with a transparent remote culture.',
      ),
      const RemoteCompany(
        title: 'Elastic',
        slug: 'elastic',
        website: 'https://www.elastic.co',
        careersUrl: 'https://www.elastic.co/about/careers',
        region: 'americas-europe',
        remotePolicy: 'remote-friendly',
        companySize: 'large',
        technologies: ['java', 'python', 'cloud'],
        blurb: 'Search solutions powered by Elasticsearch and Kibana.',
      ),
    ];

    test('Computes high match score when user skills align with tech stack', () {
      final result = service.computeMatch(
        testCompanies[0], // GitLab
        ['devops', 'kubernetes', 'aws'],
      );

      expect(result.score, greaterThanOrEqualTo(70));
      expect(result.matchedSkills, contains('devops'));
      expect(result.matchedSkills, contains('kubernetes'));
    });

    test('Filters companies by search query', () {
      final filtered = service.filterCompanies(
        companies: testCompanies,
        userSkills: ['devops'],
        query: 'buffer',
      );

      expect(filtered.length, 1);
      expect(filtered.first.company.title, 'Buffer');
    });

    test('Filters companies by region', () {
      final filtered = service.filterCompanies(
        companies: testCompanies,
        userSkills: [],
        selectedRegion: 'americas-europe',
      );

      expect(filtered.length, 1);
      expect(filtered.first.company.title, 'Elastic');
    });

    test('Filters companies by remote policy', () {
      final filtered = service.filterCompanies(
        companies: testCompanies,
        userSkills: [],
        selectedPolicy: 'fully-remote',
      );

      expect(filtered.length, 2);
      expect(filtered.map((r) => r.company.title), containsAll(['GitLab', 'Buffer']));
    });

    test('Sorts by Best Skill Match', () {
      final sorted = service.filterCompanies(
        companies: testCompanies,
        userSkills: ['kubernetes', 'devops', 'ruby'],
        sortBy: 'match',
      );

      expect(sorted.first.company.title, 'GitLab');
    });

    test('Generates generic and personalized pitch tailored to company and user', () {
      final pitch = service.generatePitch(
        company: testCompanies[0], // GitLab
        applicantName: 'Alex Doe',
        applicantRole: 'Senior DevOps & Cloud Engineer',
        skills: ['Kubernetes', 'Docker', 'AWS'],
        matchedSkills: ['Kubernetes', 'DevOps'],
      );

      expect(pitch, contains('Exploring opportunities at GitLab'));
      expect(pitch, contains('Alex Doe'));
      expect(pitch, contains('Senior DevOps & Cloud Engineer'));
      expect(pitch, contains('GitLab'));
      expect(pitch, contains('Kubernetes'));
      expect(pitch, contains('fully remote'));
    });
  });
}
