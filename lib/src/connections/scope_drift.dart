import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Scopes the server advertises that the stored grant does not carry.
///
/// Token scopes are a ceiling on the user's role permissions, so when an
/// instance widens its advertised scope set (a plugin update adding, say,
/// time tracking), existing tokens silently keep hiding those features.
/// A non-empty result means "sign in again to pick up new permissions".
///
/// An empty [granted] list means the grant's scopes are unknown (a token
/// stored before scopes were recorded); no drift is reported then, because
/// prompting would be guesswork.
List<String> newlyAdvertisedScopes({
  required List<String> granted,
  required List<String> advertised,
}) {
  final held = _normalize(granted);
  if (held.isEmpty) {
    return const [];
  }
  return _normalize(advertised).difference(held).toList();
}

/// Scope lists as sets: empty entries dropped, duplicates collapsed, so a
/// sloppy server list neither reports false drift nor changes a fingerprint.
Set<String> _normalize(List<String> scopes) =>
    scopes.where((scope) => scope.isNotEmpty).toSet();

final scopeDriftDismissalsProvider = Provider<ScopeDriftDismissals>(
  (ref) => ScopeDriftDismissals(),
);

/// Remembers, per connection, which advertised scope set the user declined
/// to re-authorize for. Declining is respected until the server's advertised
/// set changes again, so the prompt never nags but new widenings still show.
class ScopeDriftDismissals {
  ScopeDriftDismissals([SharedPreferencesAsync? prefs])
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static String _key(String connectionId) =>
      'scopeDrift.dismissed.$connectionId';

  /// A stable fingerprint of an advertised scope set, order-insensitive.
  static String _fingerprint(List<String> advertised) =>
      (_normalize(advertised).toList()..sort()).join(' ');

  Future<bool> isDismissed(String connectionId, List<String> advertised) async {
    final dismissed = await _prefs.getString(_key(connectionId));
    return dismissed == _fingerprint(advertised);
  }

  Future<void> dismiss(String connectionId, List<String> advertised) =>
      _prefs.setString(_key(connectionId), _fingerprint(advertised));

  /// Forgotten connections should leave no dismissal record behind.
  Future<void> clear(String connectionId) => _prefs.remove(_key(connectionId));
}
