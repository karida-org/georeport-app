enum ConnectionAuthKind { apiKey, oauth }

/// A saved instance: label, base URL, and how it authenticates. Secrets never
/// live here; they stay in the platform secure storage keyed by [id].
class Connection {
  const Connection({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.authKind,
  });

  factory Connection.fromJson(Map<String, dynamic> json) {
    return Connection(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      baseUrl: json['base_url'] as String? ?? '',
      authKind: json['auth_kind'] == 'oauth'
          ? ConnectionAuthKind.oauth
          : ConnectionAuthKind.apiKey,
    );
  }

  final String id;
  final String label;
  final String baseUrl;
  final ConnectionAuthKind authKind;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'base_url': baseUrl,
    'auth_kind': authKind == ConnectionAuthKind.oauth ? 'oauth' : 'api_key',
  };
}
