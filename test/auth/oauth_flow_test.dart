import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/auth/oauth_config.dart';
import 'package:georeport/src/auth/oauth_flow.dart';
import 'package:georeport/src/auth/oauth_tokens.dart';

import '../helpers/scripted_adapter.dart';

const _config = OAuthConfig(
  authorizeUrl: 'https://redmine.example.org/oauth/authorize',
  tokenUrl: 'https://redmine.example.org/oauth/token',
  clientId: 'client-abc',
  redirectUri: 'georeport://oauth/callback',
  scopes: ['view_issues', 'add_issues'],
);

void main() {
  /// Drives one authorize attempt: [respond] receives the authorize URL the
  /// flow opened and returns the callback link the browser sends back.
  ({Future<OAuthTokens> result, List<Uri> opened}) run({
    required Uri? Function(Uri authorizeUri) respond,
    List<ScriptedReply> tokenReplies = const [
      ScriptedReply(200, {
        'access_token': 'at-1',
        'refresh_token': 'rt-1',
        'expires_in': 3600,
      }),
    ],
    Duration timeout = const Duration(seconds: 5),
    bool canOpen = true,
    ScriptedAdapter? adapter,
  }) {
    final callbacks = StreamController<Uri>();
    addTearDown(callbacks.close);
    final opened = <Uri>[];
    final dio = Dio()
      ..httpClientAdapter = adapter ?? ScriptedAdapter(tokenReplies);
    final flow = OAuthFlow(
      dio: dio,
      callbackLinks: () => callbacks.stream,
      openUrl: (uri) async {
        opened.add(uri);
        if (!canOpen) {
          return false;
        }
        final reply = respond(uri);
        if (reply != null) {
          callbacks.add(reply);
        }
        return true;
      },
    );
    return (result: flow.authorize(_config, timeout: timeout), opened: opened);
  }

  /// The callback the browser would deliver for [authorizeUri]'s state.
  Uri callbackFor(Uri authorizeUri, {String? state, String code = 'the-code'}) {
    return Uri.parse('georeport://oauth/callback').replace(
      queryParameters: {
        'code': code,
        'state': state ?? authorizeUri.queryParameters['state']!,
      },
    );
  }

  group('the authorize request', () {
    test('asks for a code with PKCE and the configured scopes', () async {
      final t = run(respond: callbackFor);
      await t.result;

      final query = t.opened.single.queryParameters;
      expect(query['response_type'], 'code');
      expect(query['client_id'], 'client-abc');
      expect(query['redirect_uri'], 'georeport://oauth/callback');
      expect(query['scope'], 'view_issues add_issues');
      expect(query['code_challenge_method'], 'S256');
      expect(query['code_challenge'], isNotEmpty);
      expect(
        query['code_challenge'],
        isNot(contains(' ')),
        reason: 'the challenge travels in a URL',
      );
    });

    test('keeps query parameters the advertised URL already carried', () async {
      // A server may advertise an authorize URL with its own parameters; the
      // flow adds to them rather than replacing them.
      final callbacks = StreamController<Uri>();
      addTearDown(callbacks.close);
      final opened = <Uri>[];
      final flow = OAuthFlow(
        dio: Dio()
          ..httpClientAdapter = ScriptedAdapter([
            const ScriptedReply(200, {
              'access_token': 'at-1',
              'expires_in': 3600,
            }),
          ]),
        callbackLinks: () => callbacks.stream,
        openUrl: (uri) async {
          opened.add(uri);
          callbacks.add(callbackFor(uri));
          return true;
        },
      );
      const config = OAuthConfig(
        authorizeUrl:
            'https://redmine.example.org/oauth/authorize?tenant=north',
        tokenUrl: 'https://redmine.example.org/oauth/token',
        clientId: 'c',
        redirectUri: 'georeport://oauth/callback',
        scopes: ['view_issues'],
      );

      await flow.authorize(config, timeout: const Duration(seconds: 5));

      expect(opened.single.queryParameters['tenant'], 'north');
    });

    test('uses a different state on every attempt', () async {
      final first = run(respond: callbackFor);
      await first.result;
      final second = run(respond: callbackFor);
      await second.result;

      expect(
        first.opened.single.queryParameters['state'],
        isNot(second.opened.single.queryParameters['state']),
      );
    });
  });

  group('the callback', () {
    test('exchanges the code and returns the tokens', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply(200, {
          'access_token': 'at-1',
          'refresh_token': 'rt-1',
          'expires_in': 3600,
        }),
      ]);
      final t = run(respond: callbackFor, adapter: adapter);

      final tokens = await t.result;

      expect(tokens.accessToken, 'at-1');
      final body = adapter.requests.single.body! as Map<String, dynamic>;
      expect(body['grant_type'], 'authorization_code');
      expect(body['code'], 'the-code');
      expect(body['client_id'], 'client-abc');
      expect(
        body['code_verifier'],
        isNotEmpty,
        reason: 'PKCE: the verifier proves this is the app that started it',
      );
    });

    test('rejects a callback whose state does not match', () async {
      // The CSRF control. Without it, an attacker who can deliver a deep link
      // could hand the app a code issued for a different session.
      final adapter = ScriptedAdapter([const ScriptedReply(200)]);
      final t = run(
        respond: (uri) => callbackFor(uri, state: 'not-the-state-we-sent'),
        adapter: adapter,
      );

      await expectLater(
        t.result,
        throwsA(
          isA<OAuthFlowException>().having(
            (e) => e.message,
            'message',
            contains('state mismatch'),
          ),
        ),
      );
      expect(
        adapter.requests,
        isEmpty,
        reason: 'a rejected callback must never reach the token endpoint',
      );
    });

    test('surfaces an error the server sent back', () async {
      final t = run(
        respond: (uri) => Uri.parse('georeport://oauth/callback').replace(
          queryParameters: {
            'error': 'access_denied',
            'error_description': 'The user declined the request',
            'state': uri.queryParameters['state']!,
          },
        ),
      );

      await expectLater(
        t.result,
        throwsA(
          isA<OAuthFlowException>().having(
            (e) => e.message,
            'message',
            'The user declined the request',
          ),
        ),
      );
    });

    test('falls back to the error code when there is no description', () async {
      final t = run(
        respond: (uri) => Uri.parse('georeport://oauth/callback').replace(
          queryParameters: {
            'error': 'invalid_scope',
            'state': uri.queryParameters['state']!,
          },
        ),
      );

      await expectLater(
        t.result,
        throwsA(
          isA<OAuthFlowException>().having(
            (e) => e.message,
            'message',
            'invalid_scope',
          ),
        ),
      );
    });

    test('checks the error before the state', () async {
      // A denial carries no usable state on some servers; reporting "state
      // mismatch" would hide what actually happened from the user.
      final t = run(
        respond: (_) => Uri.parse(
          'georeport://oauth/callback?error=access_denied&state=whatever',
        ),
      );

      await expectLater(
        t.result,
        throwsA(
          isA<OAuthFlowException>().having(
            (e) => e.message,
            'message',
            'access_denied',
          ),
        ),
      );
    });

    test('rejects a callback carrying no code', () async {
      final t = run(
        respond: (uri) => Uri.parse(
          'georeport://oauth/callback',
        ).replace(queryParameters: {'state': uri.queryParameters['state']!}),
      );

      await expectLater(
        t.result,
        throwsA(
          isA<OAuthFlowException>().having(
            (e) => e.message,
            'message',
            contains('no code'),
          ),
        ),
      );
    });

    test('ignores deep links that are not the redirect', () async {
      // The app receives every link for its scheme. A share or a shortcut
      // arriving mid-sign-in must not be mistaken for the callback.
      final callbacks = StreamController<Uri>();
      addTearDown(callbacks.close);
      final flow = OAuthFlow(
        dio: Dio()
          ..httpClientAdapter = ScriptedAdapter([const ScriptedReply(200)]),
        callbackLinks: () => callbacks.stream,
        openUrl: (uri) async {
          callbacks
            ..add(Uri.parse('georeport://share/photo?id=1'))
            ..add(Uri.parse('https://example.org/oauth/callback?code=x'));
          return true;
        },
      );

      await expectLater(
        flow.authorize(_config, timeout: const Duration(milliseconds: 200)),
        throwsA(
          isA<OAuthFlowException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });
  });

  group('giving up', () {
    test('reports a browser that could not be opened', () async {
      final t = run(respond: (_) => null, canOpen: false);

      await expectLater(
        t.result,
        throwsA(
          isA<OAuthFlowException>().having(
            (e) => e.message,
            'message',
            contains('Could not open'),
          ),
        ),
      );
    });

    test('times out when no callback ever arrives', () async {
      final t = run(
        respond: (_) => null,
        timeout: const Duration(milliseconds: 200),
      );

      await expectLater(
        t.result,
        throwsA(
          isA<OAuthFlowException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });

    test('a timed-out attempt does not swallow the next one', () async {
      // The subscription is cancelled in a finally block. If it leaked, this
      // second attempt's callback would be consumed by the first listener and
      // the user could never sign in again without restarting the app.
      final callbacks = StreamController<Uri>.broadcast();
      addTearDown(callbacks.close);
      var attempt = 0;
      final flow = OAuthFlow(
        dio: Dio()
          ..httpClientAdapter = ScriptedAdapter([
            const ScriptedReply(200, {
              'access_token': 'at-2',
              'expires_in': 3600,
            }),
          ]),
        callbackLinks: () => callbacks.stream,
        openUrl: (uri) async {
          attempt += 1;
          if (attempt == 2) {
            callbacks.add(callbackFor(uri));
          }
          return true;
        },
      );

      await expectLater(
        flow.authorize(_config, timeout: const Duration(milliseconds: 200)),
        throwsA(isA<OAuthFlowException>()),
      );

      final tokens = await flow.authorize(
        _config,
        timeout: const Duration(seconds: 5),
      );
      expect(tokens.accessToken, 'at-2');
    });
  });

  group('the token response', () {
    test('rejects a body that is not a JSON object', () async {
      // A proxy or a login page answering with HTML would otherwise surface
      // as a TypeError, bypassing the Exception handling around sign-in.
      expect(
        () => tokensFromResponseBody('<html>Sign in</html>'),
        throwsA(isA<OAuthFlowException>()),
      );
    });

    test('rejects a response with no access token', () async {
      expect(
        () => tokensFromResponseBody(const {'token_type': 'Bearer'}),
        throwsA(
          isA<OAuthFlowException>().having(
            (e) => e.message,
            'message',
            contains('no access token'),
          ),
        ),
      );
    });
  });
}
