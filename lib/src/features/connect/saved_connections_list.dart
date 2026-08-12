import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../connections/connection.dart';
import '../../connections/connection_manager.dart';

enum _ConnectionAction { rename, reauthenticate, remove }

/// The saved instances on the connect screen: tap to use one; the menu
/// renames, re-authenticates in place (dead sessions keep their identity),
/// or forgets it (which also wipes its stored credentials).
class SavedConnectionsList extends ConsumerWidget {
  const SavedConnectionsList({required this.connections, super.key});

  final List<Connection> connections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        for (final connection in connections)
          _ConnectionTile(connection: connection),
      ],
    );
  }
}

class _ConnectionTile extends ConsumerWidget {
  const _ConnectionTile({required this.connection});

  final Connection connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: ListTile(
        leading: Icon(
          connection.authKind == ConnectionAuthKind.oauth
              ? Icons.account_circle
              : Icons.key,
        ),
        title: Text(connection.label),
        subtitle: Text(connection.baseUrl),
        trailing: PopupMenuButton<_ConnectionAction>(
          onSelected: (action) => switch (action) {
            _ConnectionAction.rename => _rename(context, ref),
            _ConnectionAction.reauthenticate => _reauthenticate(context, ref),
            _ConnectionAction.remove => _remove(context, ref),
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _ConnectionAction.rename,
              child: Text(l10n.connectRenameAction),
            ),
            PopupMenuItem(
              value: _ConnectionAction.reauthenticate,
              child: Text(l10n.connectReauthAction),
            ),
            PopupMenuItem(
              value: _ConnectionAction.remove,
              child: Text(l10n.connectRemoveTooltip),
            ),
          ],
        ),
        onTap: () => _activate(context, ref),
      ),
    );
  }

  /// A failed activation (dead session, offline) keeps the saved list and
  /// offers to sign in again instead of silently doing nothing.
  Future<void> _activate(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(connectionManagerProvider.notifier)
          .activate(connection.id);
      // Offline, revoked token, rotated key: user-visible situations.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.connectFailed('$error')),
          action: SnackBarAction(
            label: l10n.connectReauthAction,
            onPressed: () {
              if (context.mounted) {
                _reauthenticate(context, ref);
              }
            },
          ),
        ),
      );
    }
  }

  Future<void> _reauthenticate(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final manager = ref.read(connectionManagerProvider.notifier);
    try {
      if (connection.authKind == ConnectionAuthKind.oauth) {
        await manager.reauthenticateOAuth(connection.id);
      } else {
        final apiKey = await _promptApiKey(context, l10n);
        if (apiKey == null || apiKey.isEmpty) {
          return;
        }
        await manager.reauthenticateApiKey(connection.id, apiKey);
      }
      // The browser flow or the key validation failed; nothing was changed.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.connectFailed('$error'))),
      );
    }
  }

  Future<String?> _promptApiKey(BuildContext context, AppLocalizations l10n) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.connectNewApiKeyTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(labelText: l10n.connectApiKeyLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.connectReauthAction),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: connection.label);
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.connectRenameTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.connectRenameLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.saveButton),
          ),
        ],
      ),
    );
    if (label != null && label.trim().isNotEmpty) {
      await ref
          .read(connectionManagerProvider.notifier)
          .rename(connection.id, label);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.connectRemoveTitle),
        content: Text(l10n.connectRemoveMessage(connection.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.connectRemoveConfirm),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(connectionManagerProvider.notifier).remove(connection.id);
    }
  }
}
