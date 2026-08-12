import 'package:dio/dio.dart';

import 'oauth_flow.dart';
import 'oauth_tokens.dart';

/// The refresh operation, injectable for tests. The default implementation
/// posts a refresh_token grant to the token endpoint.
typedef TokenRefresher =
    Future<OAuthTokens> Function({
      required Dio dio,
      required String tokenUrl,
      required String clientId,
      required String refreshToken,
    });

/// Owns one connection's OAuth tokens: hands out a valid access token,
/// refreshing proactively near expiry (single-flight), and persists every
/// change through [onTokensChanged].
class TokenManager {
  TokenManager({
    required this.tokenUrl,
    required this.clientId,
    required this._tokens,
    required this.onTokensChanged,
    Dio? dio,
    this.refresher = refreshTokens,
  }) : _dio = dio ?? Dio();

  final String tokenUrl;
  final String clientId;
  final Future<void> Function(OAuthTokens tokens) onTokensChanged;
  final Dio _dio;

  /// Injectable for tests; defaults to the real token-endpoint call.
  final TokenRefresher refresher;

  OAuthTokens _tokens;
  Future<OAuthTokens>? _inflight;

  OAuthTokens get tokens => _tokens;

  /// A valid access token, refreshed first when close to expiry.
  Future<String> accessToken() async {
    if (_tokens.isExpiring() && _tokens.refreshToken != null) {
      await _refresh();
    }
    return _tokens.accessToken;
  }

  /// Forces a refresh (the 401 retry path). Returns false when there is no
  /// refresh token or the refresh fails; the caller then surfaces re-auth.
  Future<bool> forceRefresh() async {
    if (_tokens.refreshToken == null) {
      return false;
    }
    try {
      await _refresh();
      return true;
    } on Exception {
      return false;
    }
  }

  Future<void> _refresh() async {
    final inflight = _inflight;
    if (inflight != null) {
      await inflight;
      return;
    }
    final future = refresher(
      dio: _dio,
      tokenUrl: tokenUrl,
      clientId: clientId,
      refreshToken: _tokens.refreshToken!,
    );
    _inflight = future;
    try {
      var fresh = await future;
      // Doorkeeper rotates refresh tokens only when configured to; keep the
      // old one when the response omits it.
      if (fresh.refreshToken == null) {
        fresh = OAuthTokens(
          accessToken: fresh.accessToken,
          refreshToken: _tokens.refreshToken,
          expiresAt: fresh.expiresAt,
        );
      }
      _tokens = fresh;
      await onTokensChanged(fresh);
    } finally {
      _inflight = null;
    }
  }
}
