import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../api/models/bundle.dart';
import '../../api/models/geojson.dart';
import '../../api/models/gtt_style_settings.dart';
import '../../map/issue_style.dart';
import 'issues_store.dart';

class IssuesListView extends ConsumerWidget {
  const IssuesListView({
    required this.issues,
    required this.projects,
    this.style,
    super.key,
  });

  final List<BundleIssue> issues;
  final List<BundleProject> projects;
  final GttStyleSettings? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final refreshFailed = l10n.issuesRefreshFailed;
    final content = issues.isEmpty
        ? _EmptyListPlaceholder(message: l10n.issuesEmpty)
        : _buildList(context, l10n);
    return RefreshIndicator(
      onRefresh: () async {
        try {
          await ref.read(issuesProvider.notifier).refresh();
        } on Exception catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('$refreshFailed $error')));
          }
        }
      },
      child: content,
    );
  }

  Widget _buildList(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final projectNames = {
      for (final project in projects) project.id: project.name,
    };
    final dateFormat = DateFormat.MMMd(l10n.localeName);
    final today = DateTime.now();
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      // Clearance for the extended FAB over the last row.
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: issues.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final issue = issues[index];
        final summary = issue.summary;
        final statusColor = _parseHex(
          statusColorFor(summary.statusId, style?.statusColors ?? const {}),
        );
        final trackerName = style?.trackerNames[summary.trackerId];
        final statusName = style?.statusNames[summary.statusId];
        final dueDate = summary.dueDate;
        final overdue =
            dueDate != null &&
            dueDate.isBefore(DateTime(today.year, today.month, today.day));
        final metaParts = [
          ?trackerName,
          ?statusName,
          ?summary.priority,
          if (projectNames[summary.projectId] case final String name) name,
          if (summary.assignedTo case final String assignee) assignee,
        ];
        return ListTile(
          leading: Icon(
            // The geometry kind is readable straight from the list: pin,
            // route, or area, with a struck pin for unplaced issues.
            switch (issue.geometry) {
              PointGeometry() => Icons.place,
              LineGeometry() => Icons.polyline,
              PolygonGeometry() => Icons.pentagon_outlined,
              null => Icons.location_off,
            },
            color: issue.isPlaced ? statusColor : theme.colorScheme.outline,
          ),
          title: Text('#${summary.id} ${summary.subject}'),
          subtitle: Text(metaParts.join(' · ')),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (dueDate != null)
                Text(
                  dateFormat.format(dueDate),
                  style: TextStyle(
                    color: overdue ? theme.colorScheme.error : null,
                    fontWeight: overdue ? FontWeight.bold : null,
                  ),
                ),
              if (!issue.isPlaced)
                Text(l10n.issuesUnplaced, style: theme.textTheme.labelSmall),
            ],
          ),
          onTap: () => context.go('/issues/${summary.id}'),
        );
      },
    );
  }

  Color _parseHex(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return value == null ? const Color(0xFF00695C) : Color(0xFF000000 | value);
  }
}

/// Scrollable even when empty, so pull-to-refresh keeps working.
class _EmptyListPlaceholder extends StatelessWidget {
  const _EmptyListPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(child: Text(message)),
        ),
      ),
    );
  }
}
