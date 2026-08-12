import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/models/capabilities.dart';
import 'package:georeport/src/auth/oauth_config.dart';

Capabilities _capabilities({
  String authorizeUrl = 'https://demo.example.org/oauth/authorize',
  String tokenUrl = 'https://demo.example.org/oauth/token',
  Map<String, dynamic>? mobile,
}) {
  return Capabilities.fromJson({
    'plugin': 'redmine_gtt_sync',
    'version': '0.6.0',
    'redmine': {'version': '7.0.0'},
    'capabilities': const <String, dynamic>{},
    'oauth': {
      'authorize_url': authorizeUrl,
      'token_url': tokenUrl,
      'scopes': ['view_issues'],
      if (mobile != null) 'clients': {'mobile': mobile},
    },
  });
}

const _mobile = {
  'client_id': 'abc',
  'redirect_uris': ['georeport://oauth/callback'],
  'scopes': ['view_issues', 'use_gtt_sync'],
};

void main() {
  test('returns null without an advertised mobile client', () {
    expect(oauthConfigFor('https://demo.example.org', _capabilities()), isNull);
  });

  test('uses advertised same-origin endpoints and mobile scopes', () {
    final config = oauthConfigFor(
      'https://demo.example.org',
      _capabilities(mobile: _mobile),
    );

    expect(config, isNotNull);
    expect(config!.authorizeUrl, 'https://demo.example.org/oauth/authorize');
    expect(config.clientId, 'abc');
    expect(config.redirectUri, 'georeport://oauth/callback');
    expect(config.scopes, ['view_issues', 'use_gtt_sync']);
  });

  test('derives endpoints when the advertised origin differs', () {
    // A probe reached over http advertising https (or a foreign host) must
    // not steer the grant elsewhere: endpoints are derived from the base URL.
    final config = oauthConfigFor(
      'http://localhost:3000',
      _capabilities(
        authorizeUrl: 'https://localhost:3000/oauth/authorize',
        tokenUrl: 'https://evil.example.net/oauth/token',
        mobile: _mobile,
      ),
    );

    expect(config!.authorizeUrl, 'http://localhost:3000/oauth/authorize');
    expect(config.tokenUrl, 'http://localhost:3000/oauth/token');
  });

  test('ignores redirect URIs that are not ours', () {
    final config = oauthConfigFor(
      'https://demo.example.org',
      _capabilities(
        mobile: {
          'client_id': 'abc',
          'redirect_uris': ['http://127.0.0.1:7070/', 'https://x.example.org'],
          'scopes': ['view_issues'],
        },
      ),
    );

    expect(config!.redirectUri, 'georeport://oauth/callback');
  });
}
