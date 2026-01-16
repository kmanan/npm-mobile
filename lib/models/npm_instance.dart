class NpmInstance {
  final String id;
  final String name;
  final String serverUrl;
  final String email;
  final bool biometricEnabled;
  final DateTime createdAt;
  final DateTime lastUsed;

  NpmInstance({
    required this.id,
    required this.name,
    required this.serverUrl,
    required this.email,
    required this.biometricEnabled,
    required this.createdAt,
    required this.lastUsed,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'serverUrl': serverUrl,
      'email': email,
      'biometricEnabled': biometricEnabled,
      'createdAt': createdAt.toIso8601String(),
      'lastUsed': lastUsed.toIso8601String(),
    };
  }

  factory NpmInstance.fromJson(Map<String, dynamic> json) {
    return NpmInstance(
      id: json['id'] as String,
      name: json['name'] as String,
      serverUrl: json['serverUrl'] as String,
      email: json['email'] as String,
      biometricEnabled: json['biometricEnabled'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsed: DateTime.parse(json['lastUsed'] as String),
    );
  }

  NpmInstance copyWith({
    String? id,
    String? name,
    String? serverUrl,
    String? email,
    bool? biometricEnabled,
    DateTime? createdAt,
    DateTime? lastUsed,
  }) {
    return NpmInstance(
      id: id ?? this.id,
      name: name ?? this.name,
      serverUrl: serverUrl ?? this.serverUrl,
      email: email ?? this.email,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      createdAt: createdAt ?? this.createdAt,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }
}




