import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../capture/queue/queued_draft.dart';
import '../../capture/queue/upload_queue.dart';

/// A slim strip above the issue list while reports wait in the outbox:
/// count, worst state, and a tap-through to the outbox itself. Renders
/// nothing when the queue is empty, which is the normal case.
class OutboxBanner extends ConsumerWidget {
  const OutboxBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(uploadQueueProvider).value ?? const [];
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final failed = entries
        .where((entry) => entry.state == QueuedDraftState.failed)
        .length;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        color: failed > 0 ? scheme.errorContainer : scheme.secondaryContainer,
        child: ListTile(
          dense: true,
          leading: Icon(
            failed > 0 ? Icons.error_outline : Icons.cloud_upload_outlined,
          ),
          title: Text(
            failed > 0
                ? l10n.outboxBannerFailed(failed)
                : l10n.outboxBannerWaiting(entries.length),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/outbox'),
        ),
      ),
    );
  }
}
