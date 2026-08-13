import '../api/models/project_schema.dart';

/// What the user typed, turned into what the server should receive.
///
/// Two adjustments, both of which change whether a field counts as filled in:
///
/// - A required checkbox the user never touched means "off", not "not
///   answered". Redmine rejects a required bool with no value, so an untouched
///   one is sent as `'0'` rather than left out.
/// - Text is trimmed, and an all-whitespace entry drops out entirely. Otherwise
///   a space would satisfy a required field and reach the server as blank.
///
/// [fields] decides which required checkboxes get a default, but every entry
/// in [entered] is carried through, including one left behind by a tracker the
/// user switched away from. Redmine drops values for fields the tracker does
/// not have, so nothing wrong is created; see issue #81.
Map<int, Object> normalizeCustomFieldValues({
  required List<SchemaCustomField> fields,
  required Map<int, Object> entered,
}) {
  final values = <int, Object>{
    for (final field in fields)
      if (field.fieldFormat == 'bool' && field.required)
        field.id: entered[field.id] ?? '0',
  };
  for (final entry in entered.entries) {
    final value = entry.value;
    if (value is! String) {
      values[entry.key] = value;
      continue;
    }
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      values[entry.key] = trimmed;
    }
  }
  return values;
}

/// Names of the required fields [values] does not answer, in schema order.
///
/// Names rather than ids because the only caller shows them to the user.
List<String> missingRequiredFields({
  required List<SchemaCustomField> fields,
  required Map<int, Object> values,
}) {
  return [
    for (final field in fields)
      if (field.required && values[field.id] == null) field.name,
  ];
}

/// Names of the numeric fields whose entry is not a number.
///
/// Checked before submitting because Redmine answers a malformed number with a
/// validation error that is harder to act on than saying so here. `int` is
/// stricter than `float`: "1.5" is a valid float and not a valid integer.
List<String> nonNumericFields({
  required List<SchemaCustomField> fields,
  required Map<int, Object> values,
}) {
  return [
    for (final field in fields)
      if (_isNumericFormat(field.fieldFormat) &&
          values[field.id] is String &&
          !_parsesAs(field.fieldFormat, values[field.id]! as String))
        field.name,
  ];
}

bool _isNumericFormat(String fieldFormat) =>
    fieldFormat == 'int' || fieldFormat == 'float';

bool _parsesAs(String fieldFormat, String value) => fieldFormat == 'int'
    ? int.tryParse(value) != null
    : num.tryParse(value) != null;
