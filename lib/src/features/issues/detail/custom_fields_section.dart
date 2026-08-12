import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../api/models/issue_document.dart';

/// Custom field values, compact: one row per field with a set value. The
/// server already filtered them by tracker applicability and visibility.
class CustomFieldsSection extends StatelessWidget {
  const CustomFieldsSection({required this.fields, super.key});

  final List<CustomFieldValue> fields;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final withValues = fields.where((field) => field.values.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.issueCustomFieldsHeading, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final field in withValues)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(field.name, style: theme.textTheme.labelMedium),
                ),
                Expanded(child: Text(field.values.join(', '))),
              ],
            ),
          ),
      ],
    );
  }
}
