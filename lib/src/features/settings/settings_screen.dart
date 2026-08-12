import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../capture/queue/upload_queue.dart';
import 'about_section.dart';
import 'capture_defaults_section.dart';
import 'connection_section.dart';
import 'permissions_section.dart';
import 'settings_widgets.dart';

/// What the app is allowed to do and what it remembers, in one place:
/// permissions, the active connection, capture defaults, the outbox, and
/// the about block. Pushed on the root navigator from the burger menu.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(activeOutboxEntriesProvider).length;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          const PermissionsSection(),
          const ConnectionSection(),
          const CaptureDefaultsSection(),
          SettingsSection(
            title: l10n.outboxTitle,
            children: [
              ListTile(
                leading: const Icon(Icons.outbox),
                title: Text(l10n.outboxTitle),
                subtitle: Text(
                  pending == 0
                      ? l10n.outboxEmpty
                      : l10n.outboxBannerWaiting(pending),
                ),
                onTap: () => context.push('/outbox'),
              ),
            ],
          ),
          const AboutSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
