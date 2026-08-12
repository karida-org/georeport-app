import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../api/models/bundle.dart';
import '../../connections/connection_manager.dart';
import '../home/today_providers.dart';
import '../outbox/outbox_banner.dart';
import 'issues_list_view.dart';
import 'issues_maplibre_view.dart';
import 'issues_state.dart';
import 'issues_store.dart';
import 'my_work_filter.dart';

/// How an [IssuesView] presents the loaded issues.
enum IssuesViewMode { list, map }

/// The shared body of the Issues and Map screens: outbox entry point, the
/// My Work filter, and the loaded issues as a list or a map. Both screens
/// watch the same providers, so the filter selection and loaded data carry
/// over when switching between them.
class IssuesView extends ConsumerWidget {
  const IssuesView({required this.mode, super.key});

  final IssuesViewMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref.watch(issuesProvider);
    return Column(
      children: [
        // Above the async branches: while offline the issue fetch fails,
        // and that is exactly when the outbox needs its entry point.
        const OutboxBanner(),
        Expanded(child: _buildIssues(context, ref, issues)),
      ],
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
                      value: MyWorkFilter.today,
                      label: Text(l10n.myWorkFilterToday),
                      icon: const Icon(Icons.today),
                    ),
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
              child: switch (mode) {
                IssuesViewMode.list => IssuesListView(
                  issues: visible,
                  projects: data.projects,
                  style: active?.styleSettings,
                ),
                IssuesViewMode.map => IssuesMapLibreView(
                  issues: visible,
                  styleSettings: active?.styleSettings,
                ),
              },
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
    if (filter == MyWorkFilter.today) {
      // The day's plate, in list or map form: same selection as the
      // dashboard's Today card.
      return todayIssues(
        issues,
        assigneeDisplayName: displayName,
        today: DateTime.now(),
      );
    }
    return [
      for (final issue in issues)
        if (issue.summary.assignedTo == displayName) issue,
    ];
  }
}
