import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../api/models/issue_document.dart';
import '../../connections/connection_manager.dart';
import '../../map/issue_style.dart';
import '../../widgets/rich_text_body.dart';
import 'detail/attachments_section.dart';
import 'detail/custom_fields_section.dart';
import 'detail/issue_map_snippet.dart';
import 'detail/journals_section.dart';
import 'issue_providers.dart';

class IssueDetailScreen extends ConsumerWidget {
  const IssueDetailScreen({required this.issueId, super.key});

  final int issueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lives on the root navigator, outside the shell and its session guard,
    // so it carries its own: a dead session yields to the connect screen.
    ref.listen(connectionManagerProvider, (previous, next) {
      if (next.value != null && next.value!.active == null) {
        context.go('/');
      }
    });
    final l10n = AppLocalizations.of(context);
    final document = ref.watch(issueDocumentProvider(issueId));
    return Scaffold(
      appBar: AppBar(
        title: Text('#$issueId'),
        actions: [
          if (document.value case final IssueDocument issue)
            IconButton(
              icon: const Icon(Icons.link),
              tooltip: l10n.issueCopyLinkTooltip,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: issue.iri));
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.issueLinkCopied)));
                }
              },
            ),
        ],
      ),
      body: document.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text(l10n.issuesLoadFailed('$error'))),
        data: (issue) => _IssueDetail(issue: issue),
      ),
    );
  }
}

class _IssueDetail extends ConsumerWidget {
  const _IssueDetail({required this.issue});

  final IssueDocument issue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final active = ref.watch(connectionManagerProvider).value?.active;
    final style = active?.styleSettings;
    final markdown =
        active?.capabilities.textFormatting == 'common_mark' ||
        active?.capabilities.textFormatting == 'markdown';
    final dateFormat = DateFormat.yMMMd(l10n.localeName);
    final statusColor = _parseHex(
      statusColorFor(issue.status.id, style?.statusColors ?? const {}),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(issue.subject, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Chip(
              label: Text(issue.status.name),
              backgroundColor: statusColor.withValues(alpha: 0.15),
              side: BorderSide(color: statusColor),
              visualDensity: VisualDensity.compact,
            ),
            Chip(
              label: Text(issue.tracker.name),
              visualDensity: VisualDensity.compact,
            ),
            if (issue.priority case final NamedRef priority)
              Chip(
                label: Text(priority.name),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 8),
        _FieldRow(label: l10n.issueProjectLabel, value: issue.project.name),
        if (issue.author case final NamedRef author)
          _FieldRow(label: l10n.issueAuthorLabel, value: author.name),
        if (issue.assignedTo case final NamedRef assignee)
          _FieldRow(label: l10n.issueAssigneeLabel, value: assignee.name),
        if (issue.dueDate case final DateTime dueDate)
          _FieldRow(
            label: l10n.issueDueDateLabel,
            value: dateFormat.format(dueDate),
          ),
        if (issue.doneRatio > 0)
          _FieldRow(
            label: l10n.issueDoneRatioLabel,
            value: '${issue.doneRatio}%',
          ),
        if (issue.geometry != null) ...[
          const SizedBox(height: 12),
          IssueMapSnippet(issue: issue, styleSettings: style),
        ],
        if (issue.description case final String description) ...[
          const Divider(height: 32),
          RichTextBody(text: description, markdown: markdown),
        ],
        if (issue.customFields.any((field) => field.values.isNotEmpty)) ...[
          const Divider(height: 32),
          CustomFieldsSection(fields: issue.customFields),
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
          AttachmentsSection(attachments: issue.attachments),
        ],
        if (issue.journals.isNotEmpty) ...[
          const Divider(height: 32),
          JournalsSection(journals: issue.journals, markdown: markdown),
        ],
      ],
    );
  }

  Color _parseHex(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return value == null ? const Color(0xFF00695C) : Color(0xFF000000 | value);
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
