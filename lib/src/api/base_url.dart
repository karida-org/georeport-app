/// Canonical form of a user-entered instance URL: a scheme is added when
/// missing (https by default), surrounding whitespace and trailing slashes
/// are dropped. Every layer (client, OAuth config, persistence) uses this
/// one form so they can never disagree.
String normalizeBaseUrl(String url) {
  var normalized = url.trim();
  if (normalized.isEmpty) {
    return normalized;
  }
  if (!normalized.contains('://')) {
    normalized = 'https://$normalized';
  }
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}
