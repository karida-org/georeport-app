import '../api/base_url.dart';
import '../api/models/capabilities.dart';

/// The URL scheme this app registers on both platforms; only redirect URIs
/// with this scheme can ever come back to us.
const georeportScheme = 'georeport';

const _fallbackRedirectUri = 'georeport://oauth/callback';

/// Everything needed to run the authorization-code flow against one instance.
class OAuthConfig {
  const OAuthConfig({
    required this.authorizeUrl,
    required this.tokenUrl,
    required this.clientId,
    required this.redirectUri,
    required this.scopes,
  });

  final String authorizeUrl;
  final String tokenUrl;
  final String clientId;
  final String redirectUri;
  final List<String> scopes;
}

/// Builds the OAuth config for an instance from its capabilities probe, or
/// null when the instance advertises no mobile application (API key is then
/// the only rung).
///
/// Security rule (mirrors QTask): advertised endpoints are accepted only when
/// they are http(s) and same-origin with the probed base URL; anything else
/// is replaced by endpoints derived from the base URL, so a compromised or
/// misconfigured probe cannot redirect the grant elsewhere. The redirect URI
/// must carry this app's own scheme; other advertised redirects (for example
/// a desktop loopback) are ignored.
OAuthConfig? oauthConfigFor(String baseUrl, Capabilities capabilities) {
  final oauth = capabilities.oauth;
  final mobile = oauth?.mobileClient;
  if (oauth == null || mobile == null || mobile.clientId.isEmpty) {
    return null;
  }

  final base = Uri.parse(normalizeBaseUrl(baseUrl));
  final redirectUri = mobile.redirectUris.firstWhere(
    (uri) => Uri.tryParse(uri)?.scheme == georeportScheme,
    orElse: () => _fallbackRedirectUri,
  );

  return OAuthConfig(
    authorizeUrl: _sameOriginOrDerived(oauth.authorizeUrl, base, 'authorize'),
    tokenUrl: _sameOriginOrDerived(oauth.tokenUrl, base, 'token'),
    clientId: mobile.clientId,
    redirectUri: redirectUri,
    scopes: mobile.scopes,
  );
}

String _sameOriginOrDerived(String advertised, Uri base, String endpoint) {
  final derived = '${_origin(base)}/oauth/$endpoint';
  final uri = Uri.tryParse(advertised);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return derived;
  }
  final sameOrigin =
      uri.scheme == base.scheme &&
      uri.host == base.host &&
      uri.port == base.port;
  return sameOrigin ? advertised : derived;
}

String _origin(Uri base) {
  final portPart = base.hasPort ? ':${base.port}' : '';
  return '${base.scheme}://${base.host}$portPart';
}
