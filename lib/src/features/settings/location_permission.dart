import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// What the settings screen says about the location permission, and what
/// it offers to do about it.
enum LocationPermissionState {
  /// Granted (while in use or always).
  granted,

  /// Never asked, or denied but askable again: the in-app request works.
  askable,

  /// Permanently denied: only the system settings can change it.
  systemSettingsOnly,

  /// The platform could not tell (emulators without services, rare).
  unknown,
}

/// Injectable wrapper over the plugin, so the section is testable and the
/// plugin surface stays in one place.
class LocationPermissionService {
  Future<LocationPermissionState> status() async {
    return switch (await Geolocator.checkPermission()) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationPermissionState.granted,
      LocationPermission.denied => LocationPermissionState.askable,
      LocationPermission.deniedForever =>
        LocationPermissionState.systemSettingsOnly,
      LocationPermission.unableToDetermine => LocationPermissionState.unknown,
    };
  }

  Future<void> request() => Geolocator.requestPermission();

  Future<void> openSystemSettings() => Geolocator.openAppSettings();
}

final locationPermissionServiceProvider = Provider<LocationPermissionService>(
  (ref) => LocationPermissionService(),
);

/// Re-read by invalidation after a request or a return from the system
/// settings; there is no permission-change event to listen to.
final locationPermissionProvider = FutureProvider<LocationPermissionState>(
  (ref) => ref.watch(locationPermissionServiceProvider).status(),
);
