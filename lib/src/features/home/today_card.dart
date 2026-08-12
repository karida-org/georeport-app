import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../api/models/bundle.dart';
import '../../nav/maps_handoff.dart';
import 'today_providers.dart';

/// How many issues the dashboard card lists before deferring to the full
/// issue list.
const _todayCardLimit = 5;

/// The day's plate: assigned issues due today or overdue, each one tap from
/// its detail and one tap from turn-by-turn navigation. Hidden when nothing
/// is due, which is a good day.
class TodayCard extends ConsumerWidget {
  const TodayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref.watch(todayIssuesProvider);
    if (issues.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.todayCardTitle(issues.length),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final issue in issues.take(_todayCardLimit))
              _TodayRow(issue: issue),
            if (issues.length > _todayCardLimit)
              TextButton(
                onPressed: () => context.go('/issues'),
                child: Text(
                  l10n.todayCardMore(issues.length - _todayCardLimit),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TodayRow extends ConsumerWidget {
  const _TodayRow({required this.issue});

  final BundleIssue issue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final summary = issue.summary;
    final dueDate = summary.dueDate!;
    // Date-only midnight: copyWith keeps the current milliseconds, which put
    // the threshold a few hundred ms past midnight and made everything due
    // TODAY compare as overdue.
    final now = DateTime.now();
    final overdue = dueDate.isBefore(DateTime(now.year, now.month, now.day));
    final destination = representativePoint(issue.geometry);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => context.push('/issues/${summary.id}'),
      title: Text(
        '#${summary.id} ${summary.subject}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        l10n.issuesDueDate(
          DateFormat.MMMd(
            Localizations.localeOf(context).toString(),
          ).format(dueDate),
        ),
        style: TextStyle(
          color: overdue ? Theme.of(context).colorScheme.error : null,
        ),
      ),
      trailing: destination == null
          ? null
          : IconButton(
              icon: const Icon(Icons.navigation_outlined),
              tooltip: l10n.todayNavigateTooltip,
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final launched = await launchDirections(destination);
                if (!launched) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.todayNavigateFailed)),
                  );
                }
              },
            ),
    );
  }
}
