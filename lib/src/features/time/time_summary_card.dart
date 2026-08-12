import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'time_providers.dart';

/// Today's and this week's logged hours, from the contract's own-entries
/// index. Hidden on servers without the time-entry contract and while the
/// summary cannot load, keeping the dashboard calm offline.
class TimeSummaryCard extends ConsumerWidget {
  const TimeSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(timeCapabilitiesProvider).canList) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final summary = ref.watch(myTimeSummaryProvider);
    final data = summary.value;
    if (data == null) {
      return const SizedBox.shrink();
    }
    String hours(double value) => value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.schedule),
        title: Text(l10n.timeSummaryTitle),
        subtitle: Text(
          l10n.timeSummaryLine(hours(data.today), hours(data.week)),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: l10n.issuesRefreshTooltip,
          onPressed: () => ref.invalidate(myTimeSummaryProvider),
        ),
      ),
    );
  }
}
