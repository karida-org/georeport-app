/// Parsed `GET /gtt_sync/capabilities` response.
class Capabilities {
  const Capabilities({
    required this.plugin,
    required this.version,
    required this.redmineVersion,
    required this.features,
    this.textFormatting,
    this.oauth,
  });

  factory Capabilities.fromJson(Map<String, dynamic> json) {
    final redmine = json['redmine'] as Map<String, dynamic>? ?? const {};
    final features = (json['capabilities'] as Map<String, dynamic>? ?? const {})
        .map((key, value) => MapEntry(key, value == true));
    final formatting = json['formatting'] as Map<String, dynamic>?;
    final oauth = json['oauth'] as Map<String, dynamic>?;
    return Capabilities(
      plugin: json['plugin'] as String? ?? '',
      version: json['version'] as String? ?? '',
      redmineVersion: redmine['version'] as String? ?? '',
      features: features,
      textFormatting: formatting?['text_formatting'] as String?,
      oauth: oauth == null ? null : OAuthInfo.fromJson(oauth),
    );
  }

  final String plugin;
  final String version;
  final String redmineVersion;
  final Map<String, bool> features;
  final String? textFormatting;
  final OAuthInfo? oauth;

  bool supports(String feature) => features[feature] ?? false;
}

/// OAuth parameters advertised on the capabilities probe.
class OAuthInfo {
  const OAuthInfo({
    required this.authorizeUrl,
    required this.tokenUrl,
    required this.scopes,
    this.clientId,
  });

  factory OAuthInfo.fromJson(Map<String, dynamic> json) {
    return OAuthInfo(
      authorizeUrl: json['authorize_url'] as String? ?? '',
      tokenUrl: json['token_url'] as String? ?? '',
      scopes: (json['scopes'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      clientId: json['client_id'] as String?,
    );
  }

  final String authorizeUrl;
  final String tokenUrl;
  final List<String> scopes;

  /// Present only when the instance advertises a public PKCE application.
  final String? clientId;
}
