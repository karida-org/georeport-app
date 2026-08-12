import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../api/models/bundle.dart';
import '../../connections/connection_manager.dart';
import '../outbox/outbox_banner.dart';
import 'issues_list_view.dart';
import 'issues_maplibre_view.dart';
import 'issues_store.dart';

/// Which slice of the loaded issues My Work shows.
enum MyWorkFilter { mine, all }

/// Defaults to "mine" when the signed-in account is known; the whole filter
/// is hidden (and everything shown) when it is not.
final myWorkFilterProvider =
    NotifierProvider<MyWorkFilterNotifier, MyWorkFilter>(
      MyWorkFilterNotifier.new,
    );

class MyWorkFilterNotifier extends Notifier<MyWorkFilter> {
  @override
  MyWorkFilter build() {
    final user = ref
        .watch(connectionManagerProvider)
        .value
        ?.active
        ?.currentUser;
    return user == null ? MyWorkFilter.all : MyWorkFilter.mine;
  }

  void select(MyWorkFilter filter) => state = filter;
}

class IssuesScreen extends ConsumerWidget {
  const IssuesScreen({this.initialTab = 0, super.key});

  /// 0 = list, 1 = map; the dashboard's Map tile lands directly on the map.
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final issues = ref.watch(issuesProvider);

    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/capture'),
          icon: const Icon(Icons.add_a_photo),
          label: Text(l10n.captureTitle),
        ),
        appBar: AppBar(
          title: Text(l10n.issuesTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.issuesRefreshTooltip,
              onPressed: () => ref.invalidate(issuesProvider),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: l10n.disconnectTooltip,
              onPressed: () {
                ref.read(connectionManagerProvider.notifier).disconnect();
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
        body: Column(
          children: [
            // Above the async branches: while offline the issue fetch fails,
            // and that is exactly when the outbox needs its entry point.
            const OutboxBanner(),
            Expanded(child: _buildIssues(context, ref, issues)),
          ],
        ),
      ),
    );
  }

  Widget _buildIssues(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<IssuesState> issues,
  ) {
    final l10n = AppLocalizations.of(context);
    final active = ref.watch(connectionManagerProvider).value?.active;
    final currentUser = active?.currentUser;
    final filter = ref.watch(myWorkFilterProvider);
    return issues.when(
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
                onPressed: () => ref.invalidate(issuesProvider),
                child: Text(l10n.retryButton),
              ),
            ],
          ),
        ),
      ),
      data: (data) {
        final visible = _filtered(
          data.sorted,
          filter,
          currentUser?.displayName,
        );
        return Column(
          children: [
            if (currentUser != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SegmentedButton<MyWorkFilter>(
                  segments: [
                    ButtonSegment(
                      value: MyWorkFilter.mine,
                      label: Text(l10n.myWorkFilterMine),
                      icon: const Icon(Icons.person),
                    ),
                    ButtonSegment(
                      value: MyWorkFilter.all,
                      label: Text(l10n.myWorkFilterAll),
                      icon: const Icon(Icons.group),
                    ),
                  ],
                  selected: {filter},
                  onSelectionChanged: (selection) => ref
                      .read(myWorkFilterProvider.notifier)
                      .select(selection.single),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  IssuesListView(
                    issues: visible,
                    projects: data.projects,
                    style: active?.styleSettings,
                  ),
                  IssuesMapLibreView(
                    issues: visible,
                    styleSettings: active?.styleSettings,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<BundleIssue> _filtered(
    List<BundleIssue> issues,
    MyWorkFilter filter,
    String? displayName,
  ) {
    if (filter == MyWorkFilter.all || displayName == null) {
      return issues;
    }
    return [
      for (final issue in issues)
        if (issue.summary.assignedTo == displayName) issue,
    ];
  }
}
