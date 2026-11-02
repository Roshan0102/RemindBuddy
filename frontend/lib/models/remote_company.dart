class RemoteCompany {
  final String title;
  final String slug;
  final String website;
  final String careersUrl;
  final String region;
  final String remotePolicy;
  final String companySize;
  final List<String> technologies;
  final String blurb;

  const RemoteCompany({
    required this.title,
    required this.slug,
    required this.website,
    required this.careersUrl,
    required this.region,
    required this.remotePolicy,
    required this.companySize,
    required this.technologies,
    required this.blurb,
  });

  factory RemoteCompany.fromJson(Map<String, dynamic> json) {
    return RemoteCompany(
      title: (json['title'] ?? '') as String,
      slug: (json['slug'] ?? '') as String,
      website: (json['website'] ?? '') as String,
      careersUrl: (json['careersUrl'] ?? '') as String,
      region: (json['region'] ?? '') as String,
      remotePolicy: (json['remotePolicy'] ?? '') as String,
      companySize: (json['companySize'] ?? '') as String,
      technologies: (json['technologies'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      blurb: (json['blurb'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'slug': slug,
      'website': website,
      'careersUrl': careersUrl,
      'region': region,
      'remotePolicy': remotePolicy,
      'companySize': companySize,
      'technologies': technologies,
      'blurb': blurb,
    };
  }

  String get formattedRegion {
    if (region.isEmpty) return 'Global';
    return region
        .split('-')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' / ');
  }

  String get formattedRemotePolicy {
    if (remotePolicy.isEmpty) return 'Remote Friendly';
    return remotePolicy
        .split('-')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String get formattedCompanySize {
    if (companySize.isEmpty) return 'Unknown';
    return '${companySize[0].toUpperCase()}${companySize.substring(1)}';
  }
}
