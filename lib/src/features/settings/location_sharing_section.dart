import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../connections/connection_manager.dart';
import '../location/location_sharing.dart';
import 'location_permission.dart';
import 'settings_widgets.dart';

/// The opt-in for publishing your location, with the plain-language terms of
/// the deal: latest point only, who can see it, and how to stop.
class LocationSharingSection extends ConsumerStatefulWidget {
  const LocationSharingSection({super.key});

  @override
  ConsumerState<LocationSharingSection> createState() =>
      _LocationSharingSectionState();
}

class _LocationSharingSectionState
    extends ConsumerState<LocationSharingSection> {
  /// A change is being applied (the permission ask can take a while). The
  /// switch is disabled meanwhile, so a rapid on-off cannot land out of
  /// order and leave sharing on after the user turned it off.
  bool _applying = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = ref.watch(connectionManagerProvider).value?.active;
    // The server tells us whether it has the contract at all; without it the
    // toggle would promise something that cannot happen.
    if (active == null ||
        !active.capabilities.supports('user_location_publish')) {
      return const SizedBox.shrink();
    }
    final enabled = ref.watch(locationSharingEnabledProvider).value ?? false;
    final status = ref.watch(locationSharingStatusProvider);
    return SettingsSection(
      title: l10n.locationSharingHeading,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.share_location),
          title: Text(l10n.locationSharingToggle),
          subtitle: Text(l10n.locationSharingExplainer),
          isThreeLine: true,
          value: enabled,
          onChanged: _applying
              ? null
              : (value) => _setEnabled(active.connection.id, value),
        ),
        if (enabled)
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(_statusLine(context, l10n, status)),
            subtitle: Text(l10n.locationSharingForegroundNote),
          ),
      ],
    );
  }

  String _statusLine(
    BuildContext context,
    AppLocalizations l10n,
    LocationSharingStatus status,
  ) {
    final at = status.lastSharedAt;
    if (at == null) {
      return l10n.locationSharingNotYetShared;
    }
    return l10n.locationSharingLastShared(
      DateFormat.Hm(
        Localizations.localeOf(context).toString(),
      ).format(at.toLocal()),
    );
  }

  Future<void> _setEnabled(String connectionId, bool value) async {
    setState(() => _applying = true);
    try {
      if (value) {
        // Ask here, where the user just chose to share: the publisher itself
        // never prompts, so a denial simply leaves the toggle off.
        final service = ref.read(locationPermissionServiceProvider);
        if (await service.status() == LocationPermissionState.askable) {
          await service.request();
        }
        if (!mounted) {
          return;
        }
        ref.invalidate(locationPermissionProvider);
        if (await service.status() != LocationPermissionState.granted) {
          return;
        }
      }
      await ref
          .read(locationSharingPreferenceProvider)
          .setEnabled(connectionId, enabled: value);
      if (mounted) {
        ref.invalidate(locationSharingEnabledProvider);
      }
    } finally {
      if (mounted) {
        setState(() => _applying = false);
      }
    }
  }
}
