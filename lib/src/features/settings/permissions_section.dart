import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'location_permission.dart';
import 'settings_widgets.dart';

/// Live status for the location permission (the one the app can query
/// without extra plugins), plus the path to the system settings for the
/// prompt-on-first-use permissions (camera, photos).
class PermissionsSection extends ConsumerWidget {
  const PermissionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(locationPermissionProvider).value;
    return SettingsSection(
      title: l10n.settingsPermissionsHeading,
      children: [
        ListTile(
          leading: Icon(
            status == LocationPermissionState.granted
                ? Icons.location_on
                : Icons.location_off,
          ),
          title: Text(l10n.settingsLocationPermission),
          subtitle: Text(_statusLine(l10n, status)),
          trailing: switch (status) {
            LocationPermissionState.askable => TextButton(
              onPressed: () async {
                await ref.read(locationPermissionServiceProvider).request();
                ref.invalidate(locationPermissionProvider);
              },
              child: Text(l10n.settingsPermissionAllow),
            ),
            LocationPermissionState.systemSettingsOnly => TextButton(
              onPressed: () => ref
                  .read(locationPermissionServiceProvider)
                  .openSystemSettings(),
              child: Text(l10n.settingsOpenSystemSettings),
            ),
            _ => null,
          },
        ),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: Text(l10n.settingsOtherPermissions),
          subtitle: Text(l10n.settingsOtherPermissionsBody),
          trailing: TextButton(
            onPressed: () => ref
                .read(locationPermissionServiceProvider)
                .openSystemSettings(),
            child: Text(l10n.settingsOpenSystemSettings),
          ),
        ),
      ],
    );
  }

  String _statusLine(AppLocalizations l10n, LocationPermissionState? status) {
    final line = switch (status) {
      LocationPermissionState.granted => l10n.settingsPermissionGranted,
      LocationPermissionState.askable => l10n.settingsPermissionNotGranted,
      LocationPermissionState.systemSettingsOnly =>
        l10n.settingsPermissionNotGranted,
      LocationPermissionState.unknown || null => l10n.settingsPermissionUnknown,
    };
    return '$line ${l10n.settingsLocationRationale}';
  }
}
