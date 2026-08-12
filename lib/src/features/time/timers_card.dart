import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../time/issue_timer.dart';
import '../../time/timers_notifier.dart';
import 'quick_log_sheet.dart';
import 'time_providers.dart';

/// The dashboard's timers card: the running timer ticking live, paused
/// timers beneath, pause/resume and log-time actions per timer. Renders
/// nothing while no timers exist, which is the normal state.
class TimersCard extends ConsumerWidget {
  const TimersCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timers = ref.watch(timersProvider).value ?? const [];
    if (timers.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    // Tick only while something runs; a paused card is static.
    final now = timers.any((timer) => timer.isRunning)
        ? (ref.watch(tickerProvider).value ?? DateTime.now().toUtc())
        : DateTime.now().toUtc();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.timersCardTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final timer in timers) _TimerRow(timer: timer, now: now),
          ],
        ),
      ),
    );
  }
}

class _TimerRow extends ConsumerWidget {
  const _TimerRow({required this.timer, required this.now});

  final IssueTimer timer;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(timersProvider.notifier);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => context.push('/issues/${timer.issueId}'),
      title: Text(
        '#${timer.issueId} ${timer.subject}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        formatElapsed(timer.elapsed(now)),
        style: TextStyle(
          fontFeatures: const [FontFeature.tabularFigures()],
          color: timer.isRunning ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(timer.isRunning ? Icons.pause : Icons.play_arrow),
            tooltip: timer.isRunning
                ? l10n.timerPauseTooltip
                : l10n.timerStartTooltip,
            onPressed: () async {
              if (timer.isRunning) {
                await notifier.pause(timer.issueId);
              } else {
                final paused = await notifier.start(
                  issueId: timer.issueId,
                  projectId: timer.projectId,
                  subject: timer.subject,
                );
                if (paused != null && context.mounted) {
                  showAutoPauseUndo(context, ref, paused);
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline),
            tooltip: l10n.timeLogButton,
            onPressed: () => showQuickLogSheet(
              context,
              issueId: timer.issueId,
              projectId: timer.projectId,
            ),
          ),
        ],
      ),
    );
  }
}

/// h:mm:ss for a ticking timer.
String formatElapsed(Duration elapsed) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${elapsed.inHours}:${two(elapsed.inMinutes % 60)}:'
      '${two(elapsed.inSeconds % 60)}';
}

/// The one-running rule paused another timer; offer to switch back.
void showAutoPauseUndo(BuildContext context, WidgetRef ref, int pausedId) {
  final l10n = AppLocalizations.of(context);
  final notifier = ref.read(timersProvider.notifier);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(l10n.timerPausedPrevious(pausedId)),
      action: SnackBarAction(
        label: l10n.undoButton,
        onPressed: () {
          final paused = notifier.timerFor(pausedId);
          if (paused != null) {
            notifier.start(
              issueId: paused.issueId,
              projectId: paused.projectId,
              subject: paused.subject,
            );
          }
        },
      ),
    ),
  );
}
