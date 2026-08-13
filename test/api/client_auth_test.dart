import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/client_auth.dart';
import 'package:georeport/src/auth/oauth_tokens.dart';
import 'package:georeport/src/auth/token_manager.dart';

import '../helpers/scripted_adapter.dart';

/// A manager whose refresh outcome the test decides, so the interceptor can
/// be exercised without a token endpoint.
TokenManager _manager({
  required String accessToken,
  String? refreshToken = 'r1',
  OAuthTokens? refreshedTo,
  Exception? refreshFails,
  void Function()? onRefresh,
}) {
  return TokenManager(
    tokenUrl: 'https://demo.example.org/oauth/token',
    clientId: 'abc',
    tokens: OAuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
    onTokensChanged: (_) async {},
    refresher:
        ({
          required Dio dio,
          required String tokenUrl,
          required String clientId,
          required String refreshToken,
        }) async {
          onRefresh?.call();
          if (refreshFails != null) {
            throw refreshFails;
          }
          return refreshedTo ?? const OAuthTokens(accessToken: 'renewed');
        },
  );
}

Dio _dioWith(ClientAuth auth, ScriptedAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://demo.example.org'))
    ..httpClientAdapter = adapter;
  auth.install(dio);
  return dio;
}

void main() {
  group('ApiKeyAuth', () {
    test('sends the key as a header, never in the query string', () async {
      final adapter = ScriptedAdapter([const ScriptedReply(200)]);
      final dio = _dioWith(const ApiKeyAuth('secret-key'), adapter);

      await dio.get<dynamic>('/gtt_sync/capabilities');

      final request = adapter.requests.single;
      expect(request.headers['X-Redmine-API-Key'], 'secret-key');
      expect(
        request.uri.toString(),
        isNot(contains('secret-key')),
        reason: 'a key in the URL leaks into server logs and history',
      );
    });
  });

  group('OAuthAuth bearer interceptor', () {
    test('attaches the current access token to each request', () async {
      final adapter = ScriptedAdapter([const ScriptedReply(200)]);
      final dio = _dioWith(
        OAuthAuth(_manager(accessToken: 'token-1')),
        adapter,
      );

      await dio.get<dynamic>('/gtt_sync/bundle');

      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer token-1',
      );
    });

    test('heals a 401 by refreshing once and replaying the request', () async {
      // The case this exists for: a token expires mid-session and the user
      // should never see it happen.
      var refreshes = 0;
      final adapter = ScriptedAdapter([
        const ScriptedReply(401),
        const ScriptedReply(200, {'ok': true}),
      ]);
      final dio = _dioWith(
        OAuthAuth(
          _manager(accessToken: 'expired', onRefresh: () => refreshes += 1),
        ),
        adapter,
      );

      final response = await dio.get<dynamic>('/gtt_sync/bundle');

      expect(response.statusCode, 200);
      expect(refreshes, 1);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.first.headers['Authorization'], 'Bearer expired');
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer renewed',
        reason: 'the replay must carry the new token, not the dead one',
      );
    });

    test('gives up after a second 401 instead of looping', () async {
      // A server that keeps rejecting a freshly minted token means the session
      // needs real re-authorization. Retrying forever would hammer it.
      final adapter = ScriptedAdapter([const ScriptedReply(401)]);
      final dio = _dioWith(
        OAuthAuth(_manager(accessToken: 'expired')),
        adapter,
      );

      await expectLater(
        dio.get<dynamic>('/gtt_sync/bundle'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
      expect(adapter.requests, hasLength(2), reason: 'one retry, then stop');
    });

    test('surfaces the 401 when the refresh itself fails', () async {
      final adapter = ScriptedAdapter([const ScriptedReply(401)]);
      final dio = _dioWith(
        OAuthAuth(
          _manager(
            accessToken: 'expired',
            refreshFails: Exception('refresh token revoked'),
          ),
        ),
        adapter,
      );

      await expectLater(
        dio.get<dynamic>('/gtt_sync/bundle'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
      expect(
        adapter.requests,
        hasLength(1),
        reason: 'no point replaying without a new token',
      );
    });

    test('surfaces the 401 when there is no refresh token at all', () async {
      final adapter = ScriptedAdapter([const ScriptedReply(401)]);
      final dio = _dioWith(
        OAuthAuth(_manager(accessToken: 'expired', refreshToken: null)),
        adapter,
      );

      await expectLater(
        dio.get<dynamic>('/gtt_sync/bundle'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('a non-401 error is passed through untouched', () async {
      var refreshes = 0;
      final adapter = ScriptedAdapter([const ScriptedReply(403)]);
      final dio = _dioWith(
        OAuthAuth(
          _manager(accessToken: 'token-1', onRefresh: () => refreshes += 1),
        ),
        adapter,
      );

      await expectLater(
        dio.get<dynamic>('/gtt_sync/bundle'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            403,
          ),
        ),
      );
      expect(
        refreshes,
        0,
        reason: '403 is a permission answer, not a stale token',
      );
      expect(adapter.requests, hasLength(1));
    });
  });
}
