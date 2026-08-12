import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../connections/connection.dart';
import '../../connections/connection_manager.dart';

/// The saved instances on the connect screen: tap to use one, delete to
/// forget it (which also wipes its stored credentials).
class SavedConnectionsList extends ConsumerWidget {
  const SavedConnectionsList({required this.connections, super.key});

  final List<Connection> connections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final manager = ref.read(connectionManagerProvider.notifier);
    return Column(
      children: [
        for (final connection in connections)
          Card(
            child: ListTile(
              leading: Icon(
                connection.authKind == ConnectionAuthKind.oauth
                    ? Icons.account_circle
                    : Icons.key,
              ),
              title: Text(connection.label),
              subtitle: Text(connection.baseUrl),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: l10n.connectRemoveTooltip,
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(l10n.connectRemoveTitle),
                      content: Text(
                        l10n.connectRemoveMessage(connection.label),
                      ),
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
                    await manager.remove(connection.id);
                  }
                },
              ),
              onTap: () => manager.activate(connection.id),
            ),
          ),
      ],
    );
  }
}
