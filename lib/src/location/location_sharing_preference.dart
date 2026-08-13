import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the user opted into sharing their location, per connection: a
/// choice made for one instance must never leak to another.
///
/// Core rather than part of the location feature, because forgetting a
/// connection has to forget its choice, and that happens in the connection
/// manager. A preference store is not UI.
class LocationSharingPreference {
  LocationSharingPreference([SharedPreferencesAsync? prefs])
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static String _key(String connectionId) => 'location.sharing.$connectionId';

  /// Off unless the user turned it on: sharing where you are is never a
  /// default.
  Future<bool> isEnabled(String connectionId) async =>
      await _prefs.getBool(_key(connectionId)) ?? false;

  Future<void> setEnabled(String connectionId, {required bool enabled}) =>
      _prefs.setBool(_key(connectionId), enabled);

  /// Forgetting a connection forgets its choice too.
  Future<void> clear(String connectionId) => _prefs.remove(_key(connectionId));
}

final locationSharingPreferenceProvider = Provider<LocationSharingPreference>(
  (ref) => LocationSharingPreference(),
);
