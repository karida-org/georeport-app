import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../connections/connection_manager.dart';
import '../outbox/outbox_banner.dart';
import '../time/timers_card.dart';
import 'scope_drift_card.dart';
import 'today_card.dart';

/// The post-connect landing screen: glanceable state, not a browsing list.
/// Status cards only — outbox, permissions, timers, today's plate, and the
/// signed-in identity; every destination is one tap away on the bottom bar,
/// which replaced the old quick-action tiles. The shell provides the
/// scaffold, app bar, and session guard.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(connectionManagerProvider).value?.active;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const OutboxBanner(padding: EdgeInsets.only(bottom: 12)),
        const ScopeDriftCard(),
        const TimersCard(),
        const TodayCard(),
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
      ],
    );
  }
}
