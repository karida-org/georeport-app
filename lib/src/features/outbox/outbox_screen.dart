import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../capture/queue/queued_draft.dart';
import '../../capture/queue/upload_queue.dart';
import '../../shell/session_guard.dart';

/// Reports waiting to reach the server: their state, the last error, and
/// manual retry/discard. The queue itself keeps working without this screen;
/// this is the window into it. Shows only the active connection's entries,
/// matching what the queue is able to process.
class OutboxScreen extends ConsumerWidget {
  const OutboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Same state-driven session guard as the other authenticated screens.
    watchSessionEnd(ref, context);
    final l10n = AppLocalizations.of(context);
    final entries = ref.watch(activeOutboxEntriesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.outboxTitle)),
      body: entries.isEmpty
          ? Center(child: Text(l10n.outboxEmpty))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _OutboxTile(entry: entries[index]),
            ),
    );
  }
}

class _OutboxTile extends ConsumerWidget {
  const _OutboxTile({required this.entry});

  final QueuedDraft entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final failed = entry.state == QueuedDraftState.failed;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.subject, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              failed
                  ? l10n.outboxStateFailed
                  : l10n.outboxStateWaiting(entry.photos.length),
              style: TextStyle(
                color: failed ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
            if (entry.lastError case final String message) ...[
              const SizedBox(height: 4),
              Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _confirmDiscard(context, ref),
                  child: Text(l10n.outboxDiscard),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(uploadQueueProvider.notifier).retry(entry.id),
                  child: Text(l10n.outboxRetry),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDiscard(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.outboxDiscardTitle),
        content: Text(l10n.outboxDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.outboxDiscard),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(uploadQueueProvider.notifier).discard(entry.id);
    }
  }
}
