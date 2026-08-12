import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

import 'oauth_config.dart';
import 'oauth_tokens.dart';
import 'pkce.dart';

class OAuthFlowException implements Exception {
  const OAuthFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Runs the OAuth2 authorization-code + PKCE flow: opens the system browser
/// on the authorize URL, waits for the custom-scheme redirect back into the
/// app, and exchanges the code at the token endpoint.
///
/// The grant happens in the browser on purpose: the app never sees the user's
/// password, only the resulting tokens.
class OAuthFlow {
  OAuthFlow({Dio? dio, AppLinks? appLinks})
    : _dio = dio ?? Dio(),
      _appLinks = appLinks ?? AppLinks();

  final Dio _dio;
  final AppLinks _appLinks;

  Future<OAuthTokens> authorize(
    OAuthConfig config, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final pkce = PkcePair.generate();
    final state = _randomState();
    final authorizeUri = Uri.parse(config.authorizeUrl).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': config.clientId,
        'redirect_uri': config.redirectUri,
        'scope': config.scopes.join(' '),
        'state': state,
        'code_challenge': pkce.challenge,
        'code_challenge_method': 'S256',
      },
    );

    // Subscribe before launching so a fast redirect cannot be missed.
    final redirect = _appLinks.uriLinkStream
        .firstWhere((uri) => uri.scheme == georeportScheme)
        .timeout(
          timeout,
          onTimeout: () => throw const OAuthFlowException('Sign-in timed out.'),
        );

    final launched = await launchUrl(
      authorizeUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw const OAuthFlowException('Could not open the sign-in page.');
    }

    final callback = await redirect;
    final params = callback.queryParameters;
    if (params['error'] != null) {
      throw OAuthFlowException(params['error_description'] ?? params['error']!);
    }
    if (params['state'] != state) {
      throw const OAuthFlowException('Sign-in was rejected: state mismatch.');
    }
    final code = params['code'];
    if (code == null || code.isEmpty) {
      throw const OAuthFlowException('Sign-in returned no code.');
    }

    return _exchangeCode(config, code: code, verifier: pkce.verifier);
  }

  Future<OAuthTokens> _exchangeCode(
    OAuthConfig config, {
    required String code,
    required String verifier,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      config.tokenUrl,
      data: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': config.redirectUri,
        'client_id': config.clientId,
        'code_verifier': verifier,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final tokens = OAuthTokens.fromTokenResponse(response.data ?? const {});
    if (tokens.accessToken.isEmpty) {
      throw const OAuthFlowException('The server returned no access token.');
    }
    return tokens;
  }

  String _randomState() {
    final rng = Random.secure();
    return List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
  }
}

/// Exchanges a refresh token for a fresh token set. Shared by the token
/// manager; kept top-level so it has no flow/browser dependencies.
Future<OAuthTokens> refreshTokens({
  required Dio dio,
  required String tokenUrl,
  required String clientId,
  required String refreshToken,
}) async {
  final response = await dio.post<Map<String, dynamic>>(
    tokenUrl,
    data: {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': clientId,
    },
    options: Options(contentType: Headers.formUrlEncodedContentType),
  );
  final tokens = OAuthTokens.fromTokenResponse(response.data ?? const {});
  if (tokens.accessToken.isEmpty) {
    throw const OAuthFlowException('Token refresh returned no access token.');
  }
  return tokens;
}
