import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../connections/connection_manager.dart';
import 'settings_widgets.dart';

/// The active instance at a glance: who is signed in where, on what server,
/// with the switch action the burger menu also offers.
class ConnectionSection extends ConsumerWidget {
  const ConnectionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final active = ref.watch(connectionManagerProvider).value?.active;
    if (active == null) {
      return const SizedBox.shrink();
    }
    return SettingsSection(
      title: l10n.settingsConnectionHeading,
      children: [
        ListTile(
          leading: const Icon(Icons.account_circle),
          title: Text(
            active.currentUser?.displayName ?? active.connection.label,
          ),
          subtitle: Text(
            '${active.connection.baseUrl}\n'
            '${l10n.connectServerSummary(active.capabilities.redmineVersion)}',
          ),
          isThreeLine: true,
        ),
        ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: Text(l10n.menuSwitchInstance),
          onTap: () async {
            await ref.read(connectionManagerProvider.notifier).disconnect();
            if (context.mounted) {
              context.go('/');
            }
          },
        ),
      ],
    );
  }
}
