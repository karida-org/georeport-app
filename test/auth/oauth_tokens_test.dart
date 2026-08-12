import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/auth/oauth_tokens.dart';

void main() {
  test('parses granted scopes from the token response', () {
    final tokens = OAuthTokens.fromTokenResponse({
      'access_token': 'a',
      'scope': 'view_issues edit_issues log_time',
    });
    expect(tokens.scopes, ['view_issues', 'edit_issues', 'log_time']);
  });

  test('a response without scope leaves the grant unknown', () {
    final tokens = OAuthTokens.fromTokenResponse({'access_token': 'a'});
    expect(tokens.scopes, isEmpty);
  });

  test('scopes survive the storage round trip', () {
    final stored = OAuthTokens.fromJson(
      const OAuthTokens(
        accessToken: 'a',
        refreshToken: 'r',
        scopes: ['view_issues', 'log_time'],
      ).toJson(),
    );
    expect(stored.scopes, ['view_issues', 'log_time']);
    expect(stored.refreshToken, 'r');
  });
}
