import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../api/models/issue_document.dart';
import '../../../widgets/rich_text_body.dart';

/// The issue's history as a conversation: notes rendered like the
/// description, property changes as compact from/to lines.
class JournalsSection extends StatelessWidget {
  const JournalsSection({
    required this.journals,
    required this.markdown,
    super.key,
  });

  final List<JournalEntry> journals;
  final bool markdown;

  /// `status_id` reads as `status`, `done_ratio` as `done ratio`. Raw
  /// attribute names are developer-speak; this stays honest without
  /// needing a translation per Redmine field.
  static String _humanize(String name) {
    return name.replaceFirst(RegExp(r'_id$'), '').replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dateFormat = DateFormat.yMMMd(l10n.localeName).add_Hm();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.issueHistoryHeading, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final journal in journals)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          [
                            if (journal.userName case final String name) name,
                            if (journal.createdOn case final DateTime created)
                              dateFormat.format(created),
                          ].join(' · '),
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      if (journal.isPrivate)
                        Icon(
                          Icons.lock,
                          size: 14,
                          color: theme.colorScheme.outline,
                        ),
                    ],
                  ),
                  for (final detail in journal.details) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail.diffUrl != null
                          ? l10n.issueJournalEdited(_humanize(detail.name))
                          : '${_humanize(detail.name)}: '
                                '${detail.oldValue ?? l10n.issueJournalUnset}'
                                ' → '
                                '${detail.newValue ?? l10n.issueJournalUnset}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (journal.notes case final String notes) ...[
                    const SizedBox(height: 6),
                    RichTextBody(text: notes, markdown: markdown),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
