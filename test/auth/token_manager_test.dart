import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/auth/oauth_tokens.dart';
import 'package:georeport/src/auth/token_manager.dart';

void main() {
  test('returns the token untouched while fresh', () async {
    final manager = TokenManager(
      tokenUrl: 'https://demo.example.org/oauth/token',
      clientId: 'abc',
      tokens: OAuthTokens(
        accessToken: 'fresh',
        refreshToken: 'r1',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
      onTokensChanged: (_) async => fail('must not persist without refresh'),
      refresher:
          ({
            required Dio dio,
            required String tokenUrl,
            required String clientId,
            required String refreshToken,
          }) async => fail('must not refresh a fresh token'),
    );

    expect(await manager.accessToken(), 'fresh');
  });

  test(
    'refreshes an expiring token, persists, keeps old refresh token',
    () async {
      final persisted = <OAuthTokens>[];
      var refreshCalls = 0;
      final manager = TokenManager(
        tokenUrl: 'https://demo.example.org/oauth/token',
        clientId: 'abc',
        tokens: OAuthTokens(
          accessToken: 'stale',
          refreshToken: 'r1',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
        onTokensChanged: (tokens) async => persisted.add(tokens),
        refresher:
            ({
              required Dio dio,
              required String tokenUrl,
              required String clientId,
              required String refreshToken,
            }) async {
              refreshCalls += 1;
              expect(refreshToken, 'r1');
              // Doorkeeper without rotation omits the refresh token here.
              return const OAuthTokens(accessToken: 'renewed');
            },
      );

      expect(await manager.accessToken(), 'renewed');
      expect(refreshCalls, 1);
      expect(persisted.single.accessToken, 'renewed');
      expect(persisted.single.refreshToken, 'r1');
    },
  );

  test('forceRefresh reports failure without throwing', () async {
    final manager = TokenManager(
      tokenUrl: 'https://demo.example.org/oauth/token',
      clientId: 'abc',
      tokens: const OAuthTokens(accessToken: 'a', refreshToken: 'r1'),
      onTokensChanged: (_) async {},
      refresher:
          ({
            required Dio dio,
            required String tokenUrl,
            required String clientId,
            required String refreshToken,
          }) async => throw DioException(
            requestOptions: RequestOptions(path: '/oauth/token'),
          ),
    );

    expect(await manager.forceRefresh(), isFalse);
  });

  test('forceRefresh without a refresh token reports failure', () async {
    final manager = TokenManager(
      tokenUrl: 'https://demo.example.org/oauth/token',
      clientId: 'abc',
      tokens: const OAuthTokens(accessToken: 'a'),
      onTokensChanged: (_) async {},
    );

    expect(await manager.forceRefresh(), isFalse);
  });
}
