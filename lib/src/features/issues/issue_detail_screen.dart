import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../api/models/issue_document.dart';
import '../../connections/connection_manager.dart';
import '../../map/issue_style.dart';
import '../../time/timers_notifier.dart';
import '../../widgets/rich_text_body.dart';
import '../time/quick_log_sheet.dart';
import '../time/time_providers.dart';
import '../time/timers_card.dart';
import 'detail/attachments_section.dart';
import 'detail/custom_fields_section.dart';
import 'detail/edit_issue_screen.dart';
import 'detail/issue_map_snippet.dart';
import 'detail/journals_section.dart';
import 'detail/update_sheets.dart';
import 'issue_providers.dart';

class IssueDetailScreen extends ConsumerStatefulWidget {
  const IssueDetailScreen({
    required this.issueId,
    this.openQuickLog = false,
    super.key,
  });

  final int issueId;

  /// Opens the quick-log sheet once the document allows it; the timer
  /// notification's "Log time" action arrives with this set.
  final bool openQuickLog;

  @override
  ConsumerState<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends ConsumerState<IssueDetailScreen> {
  bool _quickLogOpened = false;

  int get issueId => widget.issueId;

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    // Lives on the root navigator, outside the shell and its session guard,
    // so it carries its own: a dead session yields to the connect screen.
    ref.listen(connectionManagerProvider, (previous, next) {
      if (next.value != null && next.value!.active == null) {
        context.go('/');
      }
    });
    final l10n = AppLocalizations.of(context);
    final document = ref.watch(issueDocumentProvider(issueId));
    // Time actions appear only when the server has the contract AND this
    // user may log time on this issue; the feature hides instead of 403ing.
    final canLogTime =
        ref.watch(timeCapabilitiesProvider).canCreate &&
        (document.value?.editable.canLogTime ?? false);
    // The notification's "Log time" action: open the sheet once, as soon
    // as the loaded document confirms logging is allowed here.
    if (widget.openQuickLog &&
        !_quickLogOpened &&
        canLogTime &&
        document.value != null) {
      _quickLogOpened = true;
      final projectId = document.value!.project.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showQuickLogSheet(context, issueId: issueId, projectId: projectId);
        }
      });
    }
    // Rebuild on timer changes so the play/pause toggle tracks state.
    ref.watch(timersProvider);
    final timer = ref.read(timersProvider.notifier).timerFor(issueId);
    return Scaffold(
      appBar: AppBar(
        title: Text('#$issueId'),
        actions: [
          if (document.value case final IssueDocument issue
              when canLogTime) ...[
            IconButton(
              icon: Icon(
                (timer?.isRunning ?? false) ? Icons.pause : Icons.play_arrow,
              ),
              tooltip: (timer?.isRunning ?? false)
                  ? l10n.timerPauseTooltip
                  : l10n.timerStartTooltip,
              onPressed: () async {
                final notifier = ref.read(timersProvider.notifier);
                if (timer?.isRunning ?? false) {
                  await notifier.pause(issueId);
                } else {
                  final paused = await notifier.start(
                    issueId: issueId,
                    projectId: issue.project.id,
                    subject: issue.subject,
                  );
                  if (paused != null && context.mounted) {
                    showAutoPauseUndo(context, ref, paused);
                  }
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.more_time),
              tooltip: l10n.timeLogButton,
              onPressed: () => showQuickLogSheet(
                context,
                issueId: issueId,
                projectId: issue.project.id,
              ),
            ),
          ],
          if (document.value case final IssueDocument issue
              when canEditIssue(issue))
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: l10n.editIssueTooltip,
              onPressed: () => showEditIssueScreen(context, issue: issue),
            ),
          if (document.value case final IssueDocument issue)
            // One action covers both hand-offs: the system share sheet
            // carries its own Copy, so a separate copy-link button would
            // just duplicate it.
            // Builder: the share sheet needs the button's own render box as
            // the popover anchor on iPads.
            Builder(
              builder: (context) => IconButton(
                icon: Icon(Icons.adaptive.share),
                tooltip: l10n.issueShareTooltip,
                onPressed: () {
                  final box = context.findRenderObject() as RenderBox?;
                  SharePlus.instance.share(
                    ShareParams(
                      subject: '#${issue.id} ${issue.subject}',
                      text: '#${issue.id} ${issue.subject}\n${issue.iri}',
                      sharePositionOrigin: box == null
                          ? null
                          : box.localToGlobal(Offset.zero) & box.size,
                    ),
                  );
                },
              ),
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
              // The contract only lists transitions Redmine will accept, so
              // every chip is a real one-tap action (with an optional note).
              for (final status in issue.editable.statusTransitions)
                ActionChip(
                  label: Text(status.name),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showStatusUpdateSheet(
                    context,
                    issue: issue,
                    target: status,
                  ),
                ),
            ],
          ),
        ],
        if (issue.editable.canAddNotes) ...[
          const Divider(height: 32),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_comment_outlined),
            label: Text(l10n.issueAddCommentButton),
            onPressed: () => showCommentSheet(context, issue: issue),
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
