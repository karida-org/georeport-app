import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../api/models/bundle.dart';

class IssuesListView extends StatelessWidget {
  const IssuesListView({required this.bundle, super.key});

  final Bundle bundle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (bundle.issues.isEmpty) {
      return Center(child: Text(l10n.issuesEmpty));
    }
    final projectNames = {
      for (final project in bundle.projects) project.id: project.name,
    };
    final dateFormat = DateFormat.yMMMd(l10n.localeName);
    return ListView.separated(
      itemCount: bundle.issues.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final issue = bundle.issues[index];
        final summary = issue.summary;
        final subtitleParts = [
          if (projectNames[summary.projectId] case final String name) name,
          if (summary.assignedTo case final String assignee) assignee,
          if (summary.dueDate case final DateTime dueDate)
            l10n.issuesDueDate(dateFormat.format(dueDate)),
        ];
        return ListTile(
          leading: Icon(
            issue.isPlaced ? Icons.place : Icons.location_off,
            color: issue.isPlaced
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
          title: Text('#${summary.id} ${summary.subject}'),
          subtitle: Text(
            subtitleParts.isEmpty
                ? l10n.issuesUnplaced
                : subtitleParts.join(' · '),
          ),
          trailing: issue.isPlaced ? null : Text(l10n.issuesUnplaced),
          onTap: () => context.go('/issues/${summary.id}'),
        );
      },
    );
  }
}
