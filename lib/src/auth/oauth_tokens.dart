/// An OAuth2 token set as returned by the token endpoint, serializable for
/// secure storage.
class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  factory OAuthTokens.fromTokenResponse(Map<String, dynamic> json) {
    final expiresIn = (json['expires_in'] as num?)?.toInt();
    return OAuthTokens(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String?,
      expiresAt: expiresIn == null
          ? null
          : DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
    );
  }

  factory OAuthTokens.fromJson(Map<String, dynamic> json) {
    final expiresAt = json['expires_at'] as String?;
    return OAuthTokens(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String?,
      expiresAt: expiresAt == null ? null : DateTime.tryParse(expiresAt),
    );
  }

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  /// Expired, or expiring within [leeway]. Unknown expiry counts as fresh;
  /// a stale token is then caught by the 401-refresh-retry path.
  bool isExpiring({Duration leeway = const Duration(seconds: 30)}) {
    final expiresAt = this.expiresAt;
    return expiresAt != null &&
        DateTime.now().toUtc().add(leeway).isAfter(expiresAt);
  }

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    if (refreshToken != null) 'refresh_token': refreshToken,
    if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
  };
}
