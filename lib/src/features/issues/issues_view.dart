import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../api/models/bundle.dart';
import '../../api/models/current_user.dart';
import '../../connections/connection_manager.dart';
import '../../map/map_style.dart';
import '../home/today_providers.dart';
import '../outbox/outbox_banner.dart';
import 'assignee_match.dart';
import 'issues_list_view.dart';
import 'issues_maplibre_view.dart';
import 'issues_state.dart';
import 'issues_store.dart';
import 'map_controls_sheet.dart';
import 'my_work_filter.dart';

/// How an [IssuesView] presents the loaded issues.
enum IssuesViewMode { list, map }

/// The shared body of the Issues and Map screens: outbox entry point, the
/// My Work filter, and the loaded issues as a list or a map. Both screens
/// watch the same providers, so the filter selection and loaded data carry
/// over when switching between them.
class IssuesView extends ConsumerStatefulWidget {
  const IssuesView({required this.mode, super.key});

  final IssuesViewMode mode;

  @override
  ConsumerState<IssuesView> createState() => _IssuesViewState();
}

class _IssuesViewState extends ConsumerState<IssuesView> {
  /// Held for the map-controls button beside the filter row; the map view
  /// hands it up when created and takes it back on dispose.
  MapController? _mapController;

  IssuesViewMode get mode => widget.mode;

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
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
        final visible = _filtered(data.sorted, filter, currentUser);
        final mapControls = mode == IssuesViewMode.map;
        return Column(
          children: [
            if (currentUser != null || mapControls)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    if (currentUser != null)
                      Expanded(
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
                      )
                    else
                      const Spacer(),
                    if (mapControls) ...[
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        icon: const Icon(Icons.tune),
                        tooltip: l10n.mapControlsTooltip,
                        onPressed: _mapController == null
                            ? null
                            : () => showMapControlsSheet(
                                context,
                                controller: _mapController!,
                                styleUrl: mapStyleUrl,
                              ),
                      ),
                    ],
                  ],
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
                  onController: (controller) {
                    if (mounted) {
                      setState(() => _mapController = controller);
                    }
                  },
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
    CurrentUser? user,
  ) {
    if (filter == MyWorkFilter.all || user == null) {
      return issues;
    }
    if (filter == MyWorkFilter.today) {
      // The day's plate, in list or map form: same selection as the
      // dashboard's Today card.
      return todayIssues(
        issues,
        assigneeId: user.id,
        assigneeDisplayName: user.displayName,
        today: DateTime.now(),
      );
    }
    return [
      for (final issue in issues)
        if (isAssignedTo(
          issue.summary,
          userId: user.id,
          userDisplayName: user.displayName,
        ))
          issue,
    ];
  }
}
