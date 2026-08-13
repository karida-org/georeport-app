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

/// Whether [url] can serve as an instance address at all.
///
/// Separate from [normalizeBaseUrl] because a typo is the most likely mistake
/// at the moment someone types this, and it has to be told apart from "the
/// server did not answer". Without the distinction the user gets the parser's
/// own diagnostic, caret diagram included, instead of an instruction.
///
/// Deliberately permissive: this rejects what cannot be a URL, not what is
/// unlikely to be one. A hostname with no dots is normal on a local network,
/// and http is normal for a LAN instance, so neither is refused here.
bool isUsableBaseUrl(String url) {
  final normalized = normalizeBaseUrl(url);
  if (normalized.isEmpty) {
    return false;
  }
  // A space cannot appear in an address, and Uri.tryParse does not object:
  // it percent-encodes them into the host, so "just some words" parses to a
  // host of "just%20some%20words" and would otherwise pass.
  if (normalized.contains(RegExp(r'\s'))) {
    return false;
  }
  // tryParse rather than parse: this function exists to avoid a thrown
  // FormatException reaching the screen.
  final uri = Uri.tryParse(normalized);
  if (uri == null) {
    return false;
  }
  return (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}
