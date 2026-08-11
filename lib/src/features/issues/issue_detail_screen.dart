import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../api/models/issue_document.dart';
import 'issue_providers.dart';

class IssueDetailScreen extends ConsumerWidget {
  const IssueDetailScreen({required this.issueId, super.key});

  final int issueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final document = ref.watch(issueDocumentProvider(issueId));
    return Scaffold(
      appBar: AppBar(title: Text('#$issueId')),
      body: document.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text(l10n.issuesLoadFailed('$error'))),
        data: (issue) => _IssueDetail(issue: issue),
      ),
    );
  }
}

class _IssueDetail extends StatelessWidget {
  const _IssueDetail({required this.issue});

  final IssueDocument issue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dateFormat = DateFormat.yMMMd(l10n.localeName);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(issue.subject, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Chip(label: Text(issue.tracker.name)),
            Chip(label: Text(issue.status.name)),
            if (issue.priority case final NamedRef priority)
              Chip(label: Text(priority.name)),
          ],
        ),
        const SizedBox(height: 8),
        _FieldRow(label: l10n.issueProjectLabel, value: issue.project.name),
        if (issue.assignedTo case final NamedRef assignee)
          _FieldRow(label: l10n.issueAssigneeLabel, value: assignee.name),
        if (issue.dueDate case final DateTime dueDate)
          _FieldRow(
            label: l10n.issueDueDateLabel,
            value: dateFormat.format(dueDate),
          ),
        if (issue.description case final String description) ...[
          const Divider(height: 32),
          Text(description, style: theme.textTheme.bodyMedium),
        ],
        if (issue.editable.statusTransitions.isNotEmpty) ...[
          const Divider(height: 32),
          Text(
            l10n.issueAllowedStatusChanges,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final status in issue.editable.statusTransitions)
                Chip(
                  label: Text(status.name),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
        if (issue.attachments.isNotEmpty) ...[
          const Divider(height: 32),
          Text(l10n.issueAttachmentsHeading, style: theme.textTheme.titleSmall),
          for (final attachment in issue.attachments)
            ListTile(
              dense: true,
              leading: Icon(
                attachment.isImage ? Icons.image : Icons.attach_file,
              ),
              title: Text(attachment.filename),
              subtitle: attachment.contentType == null
                  ? null
                  : Text(attachment.contentType!),
            ),
        ],
        if (issue.journals.isNotEmpty) ...[
          const Divider(height: 32),
          Text(l10n.issueHistoryHeading, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final journal in issue.journals) _JournalTile(journal: journal),
        ],
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: theme.textTheme.labelMedium),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _JournalTile extends StatelessWidget {
  const _JournalTile({required this.journal});

  final JournalEntry journal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dateFormat = DateFormat.yMMMd(l10n.localeName).add_Hm();
    final header = [
      if (journal.userName case final String name) name,
      if (journal.createdOn case final DateTime createdOn)
        dateFormat.format(createdOn),
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(header, style: theme.textTheme.labelSmall),
            if (journal.notes case final String notes) ...[
              const SizedBox(height: 6),
              Text(notes),
            ],
            if (journal.detailCount > 0) ...[
              const SizedBox(height: 6),
              Text(
                l10n.issueJournalChanges(journal.detailCount),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
