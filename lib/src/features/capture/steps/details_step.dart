import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../api/models/project_schema.dart';
import '../custom_field_editor.dart';

/// Step 4: what the issue says, and whatever the tracker requires.
///
/// Required fields are always visible; optional ones fold away behind a
/// toggle, so a tracker with many custom fields does not bury the subject
/// line under things nobody has to fill in.
class CaptureDetailsStep extends StatelessWidget {
  const CaptureDetailsStep({
    required this.subjectController,
    required this.descriptionController,
    required this.fields,
    required this.values,
    required this.onFieldChanged,
    required this.showOptional,
    required this.onToggleOptional,
    this.enabled = true,
    super.key,
  });

  final TextEditingController subjectController;
  final TextEditingController descriptionController;

  /// The tracker's editable custom fields, already filtered to the formats
  /// this app can render.
  final List<SchemaCustomField> fields;
  final Map<int, Object> values;

  /// Null clears the value, which is how "not answered" is expressed.
  final void Function(int fieldId, Object? value) onFieldChanged;

  final bool showOptional;
  final VoidCallback onToggleOptional;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final required = fields.where((field) => field.required).toList();
    final optional = fields.where((field) => !field.required).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: subjectController,
          enabled: enabled,
          decoration: InputDecoration(
            labelText: '${l10n.captureSubjectLabel} *',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: descriptionController,
          enabled: enabled,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: l10n.captureDescriptionLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        for (final field in required) ...[
          const SizedBox(height: 16),
          _editor(field),
        ],
        if (optional.isNotEmpty) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onToggleOptional,
            icon: Icon(showOptional ? Icons.expand_less : Icons.expand_more),
            label: Text(l10n.captureMoreFields),
          ),
          if (showOptional)
            for (final field in optional) ...[
              const SizedBox(height: 16),
              _editor(field),
            ],
        ],
      ],
    );
  }

  Widget _editor(SchemaCustomField field) {
    return CustomFieldEditor(
      // Keyed per field so text state never leaks across tracker switches
      // when the element tree is otherwise identical.
      key: ValueKey('cf-${field.id}'),
      field: field,
      value: values[field.id],
      onChanged: (value) => onFieldChanged(field.id, value),
    );
  }
}
