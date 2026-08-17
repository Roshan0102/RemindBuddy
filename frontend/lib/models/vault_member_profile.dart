class VaultMemberProfile {
  final String id;
  final String name;
  final String rawName;
  final String subtext;
  final int avatarColorValue;
  final bool isSelf;
  final bool isVirtual;
  final bool isCollaborator;

  VaultMemberProfile({
    required this.id,
    required this.name,
    required this.rawName,
    required this.subtext,
    required this.avatarColorValue,
    this.isSelf = false,
    this.isVirtual = false,
    this.isCollaborator = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultMemberProfile &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
