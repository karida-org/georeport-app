import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/models/project_schema.dart';

/// One editor per custom field format, driven entirely by the schema. The
/// value contract matches Redmine's API: strings (bool as '1'/'0', dates as
/// ISO), or a list of strings for multi-value fields.
class CustomFieldEditor extends StatelessWidget {
  const CustomFieldEditor({
    required this.field,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final SchemaCustomField field;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = field.required ? '${field.name} *' : field.name;
    switch (field.fieldFormat) {
      case 'list' when field.multiple:
        final selected = value is List
            ? (value! as List).whereType<String>().toSet()
            : <String>{};
        return InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final option in field.possibleValues)
                FilterChip(
                  label: Text(option),
                  selected: selected.contains(option),
                  onSelected: (on) {
                    final next = {...selected};
                    on ? next.add(option) : next.remove(option);
                    onChanged(next.isEmpty ? null : next.toList());
                  },
                ),
            ],
          ),
        );
      case 'list':
        return DropdownButtonFormField<String>(
          initialValue: value as String?,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final option in field.possibleValues)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: onChanged,
        );
      case 'bool':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: value == '1',
          onChanged: (on) => onChanged(on ? '1' : '0'),
        );
      case 'date':
        return _DateField(
          label: label,
          value: value as String?,
          onChanged: onChanged,
        );
      case 'int' || 'float':
        return TextFormField(
          initialValue: value as String?,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (text) => onChanged(text.isEmpty ? null : text),
        );
      default:
        return TextFormField(
          initialValue: value as String?,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          maxLines: field.fieldFormat == 'text' ? 3 : 1,
          onChanged: (text) => onChanged(text.isEmpty ? null : text),
        );
    }
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final parsed = value == null ? null : DateTime.tryParse(value!);
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: parsed ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          onChanged(
            '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}',
          );
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today),
        ),
        child: Text(
          parsed == null ? '' : DateFormat.yMMMd(locale).format(parsed),
        ),
      ),
    );
  }
}
