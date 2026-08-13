import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../capture/device_location.dart';
import '../../connections/connection_manager.dart';
import '../../location/location_sharing_preference.dart';
import '../../net/connectivity.dart';

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

  // Send history belongs to the connection it was gathered for: another
  // instance must not inherit its throttling window or its shown time.
  String? lastSentConnectionId;
  DateTime? lastSentAt;
  LatLng? lastSentPoint;
  var sending = false;

  String? activeConnectionId() =>
      ref.read(connectionManagerProvider).value?.active?.connection.id;

  Future<void> publish({required bool force}) async {
    if (sending || !ref.read(isOnlineProvider)) {
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return;
    }
    // Everything below is bound to THIS connection: getting a fix takes
    // seconds, and in that window the user can opt out or switch instances.
    final connectionId = activeConnectionId();
    if (connectionId == null) {
      return;
    }
    final preference = ref.read(locationSharingPreferenceProvider);
    if (!await preference.isEnabled(connectionId)) {
      return;
    }
    final client = ref.read(connectionManagerProvider).value?.active?.client;
    if (client == null || !ref.mounted) {
      return;
    }
    final now = DateTime.now();
    // A different connection than the last send has no history to throttle
    // against, so its first publish always goes out.
    final sameConnection = lastSentConnectionId == connectionId;
    final since = sameConnection ? lastSentAt : null;
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
      // Re-checked after the await: opting out, or switching instances,
      // while a fix was in flight must cancel the publish entirely.
      if (activeConnectionId() != connectionId ||
          !await preference.isEnabled(connectionId) ||
          !ref.mounted) {
        return;
      }
      final previous = sameConnection ? lastSentPoint : null;
      if (!force &&
          previous != null &&
          distance.as(LengthUnit.Meter, previous, point) < minMoveMeters) {
        return;
      }
      await client.publishLocation(point.latitude, point.longitude);
      if (!ref.mounted) {
        return;
      }
      lastSentConnectionId = connectionId;
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

  void forgetSendHistory() {
    lastSentConnectionId = null;
    lastSentAt = null;
    lastSentPoint = null;
    ref.read(locationSharingStatusProvider.notifier).reset();
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
      forgetSendHistory();
    }
  });

  // Switching instances starts over: the new connection's own opt-in
  // decides, and nothing from the previous one is shown or reused.
  ref.listen(
    connectionManagerProvider.select(
      (state) => state.value?.active?.connection.id,
    ),
    (previous, next) {
      if (previous == next) {
        return;
      }
      forgetSendHistory();
      if (next != null) {
        publish(force: true);
      }
    },
  );
});
