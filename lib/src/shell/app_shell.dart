import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../l10n/generated/app_localizations.dart';
import '../connections/connection_manager.dart';
import '../issues/sync_status.dart';
import '../net/connectivity.dart';
import 'bottom_bar.dart';
import 'session_guard.dart';

enum _MenuAction { settings, switchInstance }

/// The signed-in scaffold: one branded app bar (mark + wordmark, overflow
/// menu) and the five-slot bottom bar over the stateful shell branches.
/// Full-screen flows (capture, issue detail, outbox) push on the root
/// navigator, above both bars. There is no manual refresh: the list pulls
/// to refresh and the issues store polls the change feed on an interval;
/// the menu shows how that is going.
class AppShell extends ConsumerWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One session guard for every branch behind the bar: when the session
    // ends, the whole shell yields to the connect screen.
    watchSessionEnd(ref, context);
    final l10n = AppLocalizations.of(context);
    final active = ref.watch(connectionManagerProvider).value?.active;
    final sync = ref.watch(syncStatusProvider);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SvgPicture.asset(
              Theme.of(context).brightness == Brightness.dark
                  ? 'assets/brand/georeport-mark-dark.svg'
                  : 'assets/brand/georeport-mark.svg',
              height: 28,
            ),
            const SizedBox(width: 10),
            Text(l10n.appTitle),
          ],
        ),
        actions: [
          PopupMenuButton<_MenuAction>(
            icon: const Icon(Icons.menu),
            tooltip: l10n.navMenuTooltip,
            onSelected: (action) async {
              switch (action) {
                case _MenuAction.settings:
                  // The push future completes when the screen pops; nothing
                  // to do with it here.
                  unawaited(context.push('/settings'));
                case _MenuAction.switchInstance:
                  await ref
                      .read(connectionManagerProvider.notifier)
                      .disconnect();
                  if (context.mounted) {
                    context.go('/');
                  }
              }
            },
            itemBuilder: (context) => [
              if (active != null)
                PopupMenuItem<_MenuAction>(
                  enabled: false,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_circle),
                    title: Text(
                      active.currentUser?.displayName ??
                          active.connection.label,
                    ),
                    subtitle: Text(active.connection.label),
                  ),
                ),
              if (active != null)
                PopupMenuItem<_MenuAction>(
                  enabled: false,
                  child: _syncStatusTile(context, ref, l10n, sync),
                ),
              if (active != null) const PopupMenuDivider(),
              PopupMenuItem<_MenuAction>(
                value: _MenuAction.settings,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(l10n.settingsTitle),
                ),
              ),
              PopupMenuItem<_MenuAction>(
                value: _MenuAction.switchInstance,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(l10n.menuSwitchInstance),
                ),
              ),
            ],
          ),
        ],
      ),
      body: shell,
      bottomNavigationBar: GeoreportBottomBar(shell: shell),
    );
  }

  /// Three connection states, calmest first: an offline device is a normal
  /// part of field work (neutral), a healthy sync is good news (primary),
  /// and a failing server on a working network is the one worth alarm
  /// (error). Whatever the state, the last successful sync time stays.
  Widget _syncStatusTile(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    SyncStatus sync,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final online = ref.watch(isOnlineProvider);
    final (icon, color, label) = switch ((online, sync.healthy)) {
      (false, _) => (
        Icons.cloud_off,
        scheme.onSurfaceVariant,
        l10n.menuOffline,
      ),
      (true, true) => (Icons.cloud_done, scheme.primary, l10n.menuConnectionOk),
      (true, false) => (
        Icons.cloud_off,
        scheme.error,
        l10n.menuConnectionProblem,
      ),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(label),
      subtitle: sync.lastSyncAt == null
          ? null
          : Text(
              l10n.menuLastSync(
                DateFormat.Hm(
                  Localizations.localeOf(context).toString(),
                ).format(sync.lastSyncAt!.toLocal()),
              ),
            ),
    );
  }
}
