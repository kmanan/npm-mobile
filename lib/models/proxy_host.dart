class ProxyHost {
  final int id;
  final List<String> domainNames;
  final String forwardScheme;
  final String forwardHost;
  final int forwardPort;
  final int? accessListId;
  final int? certificateId;
  final bool sslForced;
  final bool enabled;

  ProxyHost({
    required this.id,
    required this.domainNames,
    required this.forwardScheme,
    required this.forwardHost,
    required this.forwardPort,
    this.accessListId,
    this.certificateId,
    required this.sslForced,
    required this.enabled,
  });

  factory ProxyHost.fromJson(Map<String, dynamic> json) {
    return ProxyHost(
      id: json['id'] as int,
      domainNames: List<String>.from(json['domain_names']),
      forwardScheme: json['forward_scheme'] as String,
      forwardHost: json['forward_host'] as String,
      forwardPort: json['forward_port'] as int,
      accessListId: json['access_list_id'] as int?,
      certificateId: json['certificate_id'] as int?,
      sslForced: json['ssl_forced'] as bool,
      enabled: json['enabled'] as bool,
    );
  }
}