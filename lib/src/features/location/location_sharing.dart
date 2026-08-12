import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../capture/device_location.dart';
import '../../connections/connection_manager.dart';
import '../../features/issues/issue_providers.dart';
import '../../net/connectivity.dart';

/// Whether the user opted into sharing their location, per connection: a
/// choice made for one instance must never leak to another.
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

final locationSharingEnabledProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final connectionId = ref.watch(
    connectionManagerProvider.select(
      (state) => state.value?.active?.connection.id,
    ),
  );
  if (connectionId == null) {
    return false;
  }
  return ref.watch(locationSharingPreferenceProvider).isEnabled(connectionId);
});

/// What the UI reports about sharing.
class LocationSharingStatus {
  const LocationSharingStatus({this.lastSharedAt, this.lastError});

  final DateTime? lastSharedAt;
  final String? lastError;
}

final locationSharingStatusProvider =
    NotifierProvider<LocationSharingStatusNotifier, LocationSharingStatus>(
      LocationSharingStatusNotifier.new,
    );

class LocationSharingStatusNotifier extends Notifier<LocationSharingStatus> {
  @override
  LocationSharingStatus build() => const LocationSharingStatus();

  void recordShared(DateTime at) =>
      state = LocationSharingStatus(lastSharedAt: at);

  void recordFailure(String error) => state = LocationSharingStatus(
    lastSharedAt: state.lastSharedAt,
    lastError: error,
  );

  void reset() => state = const LocationSharingStatus();
}

/// Publishes the user's position while sharing is on and the app is in use.
///
/// Deliberately foreground-only for now: continuous background sharing needs
/// a transport decision (see issue #50) — either a server that accepts the
/// Traccar protocol on a device token, or hand-rolled background collection.
/// Neither belongs in the same change as the opt-in itself, and this way the
/// feature ships without a second credential type or a battery risk.
///
/// Cheap by construction: a position is only sent when the device has moved
/// at least [_minMoveMeters], and never more often than [_minInterval].
final locationSharingProvider = Provider<void>((ref) {
  const minInterval = Duration(minutes: 2);
  const minMoveMeters = 50.0;
  const distance = Distance();

  DateTime? lastSentAt;
  LatLng? lastSentPoint;
  var sending = false;

  Future<void> publish({required bool force}) async {
    final enabled = await ref.read(locationSharingEnabledProvider.future);
    if (!enabled || sending || !ref.read(isOnlineProvider)) {
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return;
    }
    final now = DateTime.now();
    final since = lastSentAt;
    if (!force && since != null && now.difference(since) < minInterval) {
      return;
    }
    sending = true;
    try {
      // Never prompts: sharing is only ever published from a permission the
      // user already granted, and the settings toggle is where the ask
      // happens.
      final point = await currentDeviceLocation();
      if (point == null || !ref.mounted) {
        return;
      }
      final previous = lastSentPoint;
      if (!force &&
          previous != null &&
          distance.as(LengthUnit.Meter, previous, point) < minMoveMeters) {
        return;
      }
      await ref
          .read(activeClientProvider)
          .publishLocation(point.latitude, point.longitude);
      if (!ref.mounted) {
        return;
      }
      lastSentAt = now;
      lastSentPoint = point;
      ref.read(locationSharingStatusProvider.notifier).recordShared(now);
    } on Exception catch (error) {
      if (ref.mounted) {
        ref
            .read(locationSharingStatusProvider.notifier)
            .recordFailure('$error');
      }
    } finally {
      sending = false;
    }
  }

  final timer = Timer.periodic(minInterval, (_) => publish(force: false));
  // Returning to the app is when a dispatcher's view is most likely stale.
  final lifecycle = AppLifecycleListener(onResume: () => publish(force: false));
  ref.onDispose(() {
    timer.cancel();
    lifecycle.dispose();
  });

  // Turning the toggle on publishes immediately, so the user sees it work
  // instead of waiting out an interval.
  ref.listen(locationSharingEnabledProvider, (previous, next) {
    if (next.value == true && previous?.value != true) {
      publish(force: true);
    }
    if (next.value == false && previous?.value == true) {
      lastSentAt = null;
      lastSentPoint = null;
      ref.read(locationSharingStatusProvider.notifier).reset();
    }
  });
});
