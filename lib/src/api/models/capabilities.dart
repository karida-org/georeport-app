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
    this.mobileClient,
  });

  factory OAuthInfo.fromJson(Map<String, dynamic> json) {
    final clients = json['clients'] as Map<String, dynamic>?;
    final mobile = clients?['mobile'];
    return OAuthInfo(
      authorizeUrl: json['authorize_url'] as String? ?? '',
      tokenUrl: json['token_url'] as String? ?? '',
      scopes: (json['scopes'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      clientId: json['client_id'] as String?,
      mobileClient: mobile is Map<String, dynamic>
          ? OAuthClientInfo.fromJson(mobile)
          : null,
    );
  }

  final String authorizeUrl;
  final String tokenUrl;

  /// The scopes advertised for the desktop client (top-level back-compat
  /// field); mobile clients use [mobileClient]'s own scope list.
  final List<String> scopes;

  /// The desktop (QTask) client id; present only when advertised.
  final String? clientId;

  /// The advertised mobile application, when the instance has one set up.
  /// Its presence is what makes zero-config OAuth sign-in available.
  final OAuthClientInfo? mobileClient;
}

/// One entry of the probe's `oauth.clients` map: a public PKCE application
/// advertised for a specific client kind.
class OAuthClientInfo {
  const OAuthClientInfo({
    required this.clientId,
    required this.redirectUris,
    required this.scopes,
  });

  factory OAuthClientInfo.fromJson(Map<String, dynamic> json) {
    return OAuthClientInfo(
      clientId: json['client_id'] as String? ?? '',
      redirectUris: (json['redirect_uris'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      scopes: (json['scopes'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }

  final String clientId;
  final List<String> redirectUris;
  final List<String> scopes;
}
