import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../connect/connection_provider.dart';
import 'issue_providers.dart';
import 'issues_list_view.dart';
import 'issues_map_view.dart';

class IssuesScreen extends ConsumerWidget {
  const IssuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bundle = ref.watch(bundleProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.issuesTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.issuesRefreshTooltip,
              onPressed: () => ref.invalidate(bundleProvider),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: l10n.disconnectTooltip,
              onPressed: () {
                ref.read(connectionProvider.notifier).disconnect();
                context.go('/');
              },
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.issuesListTab),
              Tab(text: l10n.issuesMapTab),
            ],
          ),
        ),
        body: bundle.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.issuesLoadFailed('$error'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(bundleProvider),
                    child: Text(l10n.retryButton),
                  ),
                ],
              ),
            ),
          ),
          data: (data) => TabBarView(
            children: [
              IssuesListView(bundle: data),
              IssuesMapView(bundle: data),
            ],
          ),
        ),
      ),
    );
  }
}
