import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../connections/connection_manager.dart';
import '../outbox/outbox_banner.dart';
import '../time/time_summary_card.dart';
import '../time/timers_card.dart';

/// The post-connect landing screen: glanceable state and one-tap actions
/// instead of a browsing list. v1 carries the connection card, quick actions,
/// and the outbox chip; the timers card and time summaries land with the
/// time-tracking work (#14, #38).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Same state-driven session guard as the other authenticated screens.
    ref.listen(connectionManagerProvider, (previous, next) {
      if (next.value != null && next.value!.active == null) {
        context.go('/');
      }
    });
    final l10n = AppLocalizations.of(context);
    final active = ref.watch(connectionManagerProvider).value?.active;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l10n.disconnectTooltip,
            onPressed: () {
              ref.read(connectionManagerProvider.notifier).disconnect();
              context.go('/');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const OutboxBanner(padding: EdgeInsets.only(bottom: 12)),
          const TimersCard(),
          const TimeSummaryCard(),
          if (active != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_circle),
                title: Text(
                  active.currentUser?.displayName ?? active.connection.label,
                ),
                subtitle: Text(active.connection.label),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ActionTile(
                  icon: Icons.add_a_photo,
                  label: l10n.captureTitle,
                  onTap: () => context.push('/capture'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionTile(
                  icon: Icons.checklist,
                  label: l10n.homeActionIssues,
                  onTap: () => context.go('/issues'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionTile(
                  icon: Icons.map_outlined,
                  label: l10n.issuesMapTab,
                  onTap: () => context.go('/issues?tab=map'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Icon(icon, color: scheme.onSecondaryContainer),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
