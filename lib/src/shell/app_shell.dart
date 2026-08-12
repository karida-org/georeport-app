import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../connections/connection_manager.dart';

/// The signed-in scaffold: a bottom navigation bar over the stateful shell
/// branches (Home and Issues). Full-screen flows (capture, issue detail,
/// outbox) push on the root navigator, above this bar.
class AppShell extends ConsumerWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One session guard for every branch behind the bar: when the session
    // ends, the whole shell yields to the connect screen.
    ref.listen(connectionManagerProvider, (previous, next) {
      if (next.value != null && next.value!.active == null) {
        context.go('/');
      }
    });
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) => shell.goBranch(
          index,
          // Re-tapping the active destination pops its branch to the root,
          // the platform-conventional "go home" gesture.
          initialLocation: index == shell.currentIndex,
        ),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.checklist_outlined),
            selectedIcon: const Icon(Icons.checklist),
            label: l10n.navIssues,
          ),
        ],
      ),
    );
  }
}
