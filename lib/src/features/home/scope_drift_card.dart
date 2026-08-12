import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../connections/connection_manager.dart';
import '../../connections/scope_drift.dart';

/// The scopes to invite a re-authorization for: the active session's drift,
/// unless the user already declined this exact advertised set. Empty hides
/// the card.
final scopeDriftPromptProvider = FutureProvider<List<String>>((ref) async {
  final active = ref.watch(
    connectionManagerProvider.select((state) => state.value?.active),
  );
  if (active == null || active.newScopes.isEmpty) {
    return const [];
  }
  final advertised =
      active.capabilities.oauth?.mobileClient?.scopes ?? const <String>[];
  final dismissed = await ref
      .watch(scopeDriftDismissalsProvider)
      .isDismissed(active.connection.id, advertised);
  return dismissed ? const [] : active.newScopes;
});

/// A non-blocking dashboard invitation to sign in again when the server
/// advertises OAuth scopes the current grant does not carry (a plugin update
/// added features the token cannot see). Declining is remembered until the
/// advertised set changes again.
class ScopeDriftCard extends ConsumerWidget {
  const ScopeDriftCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newScopes = ref.watch(scopeDriftPromptProvider).value ?? const [];
    if (newScopes.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_open, color: scheme.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.scopeDriftTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.scopeDriftBody,
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _dismiss(ref),
                  child: Text(l10n.scopeDriftNotNow),
                ),
                TextButton(
                  onPressed: () => _reauthorize(context, ref),
                  child: Text(l10n.connectReauthAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _dismiss(WidgetRef ref) async {
    final active = ref.read(connectionManagerProvider).value?.active;
    if (active == null) {
      return;
    }
    await ref
        .read(scopeDriftDismissalsProvider)
        .dismiss(
          active.connection.id,
          active.capabilities.oauth?.mobileClient?.scopes ?? const [],
        );
    ref.invalidate(scopeDriftPromptProvider);
  }

  Future<void> _reauthorize(BuildContext context, WidgetRef ref) async {
    final active = ref.read(connectionManagerProvider).value?.active;
    if (active == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Success replaces the stored tokens and re-activates the session,
      // which recomputes the drift to empty; the card retires itself.
      await ref
          .read(connectionManagerProvider.notifier)
          .reauthenticateOAuth(active.connection.id);
      // The browser flow failed or was abandoned; nothing was changed.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.connectFailed('$error'))),
      );
    }
  }
}
