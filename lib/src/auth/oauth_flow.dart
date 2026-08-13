import 'dart:async';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

import 'oauth_config.dart';
import 'oauth_tokens.dart';
import 'pkce.dart';

/// Opens [uri] outside the app, returning false when nothing could handle it.
///
/// A seam, so the flow's own logic (state matching, the error parameter, the
/// timeout) can be exercised without a browser. Defaults to the system
/// browser, which is where the grant has to happen.
typedef UrlOpener = Future<bool> Function(Uri uri);

/// The deep links arriving back into the app.
///
/// A function rather than a stream because it is subscribed to per attempt,
/// matching how the underlying platform stream is consumed.
typedef CallbackLinks = Stream<Uri> Function();

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
  OAuthFlow({
    Dio? dio,
    UrlOpener? openUrl,
    CallbackLinks? callbackLinks,
    AppLinks? appLinks,
  }) : _dio = dio ?? Dio(),
       _openUrl = openUrl ?? _openInSystemBrowser,
       // Lazily: constructing AppLinks touches a platform channel, which a
       // test supplying its own stream must not have to stand up.
       _callbackLinks = callbackLinks ?? _linksFrom(appLinks);

  final Dio _dio;
  final UrlOpener _openUrl;
  final CallbackLinks _callbackLinks;

  static CallbackLinks _linksFrom(AppLinks? provided) {
    final links = provided ?? AppLinks();
    return () => links.uriLinkStream;
  }

  static Future<bool> _openInSystemBrowser(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<OAuthTokens> authorize(
    OAuthConfig config, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final pkce = PkcePair.generate();
    final state = _randomState();
    final baseAuthorizeUri = Uri.parse(config.authorizeUrl);
    final authorizeUri = baseAuthorizeUri.replace(
      queryParameters: {
        // Anything already carried by the advertised URL stays.
        ...baseAuthorizeUri.queryParameters,
        'response_type': 'code',
        'client_id': config.clientId,
        'redirect_uri': config.redirectUri,
        'scope': config.scopes.join(' '),
        'state': state,
        'code_challenge': pkce.challenge,
        'code_challenge_method': 'S256',
      },
    );

    // Subscribe before launching so a fast redirect cannot be missed, and
    // always cancel the subscription: a timeout or a failed exchange must
    // not leave a listener that swallows a later attempt's callback.
    final expected = Uri.parse(config.redirectUri);
    final completer = Completer<Uri>();
    final subscription = _callbackLinks().listen((uri) {
      final matches =
          uri.scheme == expected.scheme &&
          uri.host == expected.host &&
          uri.path == expected.path;
      if (matches && !completer.isCompleted) {
        completer.complete(uri);
      }
    });

    final Uri callback;
    try {
      final launched = await _openUrl(authorizeUri);
      if (!launched) {
        throw const OAuthFlowException('Could not open the sign-in page.');
      }
      callback = await completer.future.timeout(
        timeout,
        onTimeout: () => throw const OAuthFlowException('Sign-in timed out.'),
      );
    } finally {
      await subscription.cancel();
    }
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
    final response = await _dio.post<dynamic>(
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
    return tokensFromResponseBody(response.data);
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
  final response = await dio.post<dynamic>(
    tokenUrl,
    data: {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': clientId,
    },
    options: Options(contentType: Headers.formUrlEncodedContentType),
  );
  return tokensFromResponseBody(response.data);
}

/// The token endpoint's body as tokens, tolerating a non-map body (wrong
/// content type, HTML error page) by failing with a typed exception instead
/// of a TypeError that would bypass Exception-based handling.
OAuthTokens tokensFromResponseBody(Object? body) {
  if (body is! Map<String, dynamic>) {
    throw const OAuthFlowException(
      'The server returned an unexpected token response.',
    );
  }
  final tokens = OAuthTokens.fromTokenResponse(body);
  if (tokens.accessToken.isEmpty) {
    throw const OAuthFlowException('The server returned no access token.');
  }
  return tokens;
}
