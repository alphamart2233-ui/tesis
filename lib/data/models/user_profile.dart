class UserProfile {
  final String uid;
  final String email;
  final String? displayName;
  final Map<String, dynamic> settings;
  final int? lastSyncAt;
  final String? appVersion;

  UserProfile({
    required this.uid,
    required this.email,
    this.displayName,
    required this.settings,
    this.lastSyncAt,
    this.appVersion,
  });

  factory UserProfile.fromMap(String uid, Map<String, dynamic> m) => UserProfile(
    uid: uid,
    email: m['email'] ?? '',
    displayName: m['displayName'],
    settings: Map<String, dynamic>.from(m['settings'] ?? const {}),
    lastSyncAt: (m['lastSyncAt'] is int) ? m['lastSyncAt'] as int : null,
    appVersion: m['appVersion'],
  );

  Map<String, dynamic> toMap() => {
    'email': email,
    'displayName': displayName,
    'settings': settings,
    'lastSyncAt': lastSyncAt,
    'appVersion': appVersion,
    // timestamps los setea el repositorio
  };
}
