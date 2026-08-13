import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/models/project_schema.dart';
import 'package:georeport/src/capture/custom_field_values.dart';

SchemaCustomField _field({
  required int id,
  required String name,
  String fieldFormat = 'string',
  bool required = false,
  bool multiple = false,
}) {
  return SchemaCustomField(
    id: id,
    name: name,
    fieldFormat: fieldFormat,
    required: required,
    multiple: multiple,
    possibleValues: const [],
    trackerIds: const [],
  );
}

void main() {
  group('normalizeCustomFieldValues', () {
    test('trims text, since a space is not an answer', () {
      final values = normalizeCustomFieldValues(
        fields: [_field(id: 1, name: 'Note')],
        entered: {1: '  hello  '},
      );

      expect(values[1], 'hello');
    });

    test('drops an all-whitespace entry so it can fail the required check', () {
      // The bug this prevents: a space satisfies "required" and the issue is
      // created with an empty field.
      final values = normalizeCustomFieldValues(
        fields: [_field(id: 1, name: 'Note', required: true)],
        entered: {1: '   '},
      );

      expect(values.containsKey(1), isFalse);
      expect(
        missingRequiredFields(
          fields: [_field(id: 1, name: 'Note', required: true)],
          values: values,
        ),
        ['Note'],
      );
    });

    test('sends an untouched required checkbox as off, not as missing', () {
      // Redmine rejects a required bool with no value at all, and a checkbox
      // the user never touched genuinely means "no".
      final values = normalizeCustomFieldValues(
        fields: [
          _field(id: 4, name: 'Verified', fieldFormat: 'bool', required: true),
        ],
        entered: const {},
      );

      expect(values[4], '0');
    });

    test('leaves an optional untouched checkbox out entirely', () {
      final values = normalizeCustomFieldValues(
        fields: [_field(id: 4, name: 'Verified', fieldFormat: 'bool')],
        entered: const {},
      );

      expect(values, isEmpty);
    });

    test('keeps non-string values as they are', () {
      // Multi-select values arrive as lists and must not be stringified.
      final values = normalizeCustomFieldValues(
        fields: [
          _field(id: 7, name: 'Tags', fieldFormat: 'list', multiple: true),
        ],
        entered: {
          7: ['a', 'b'],
        },
      );

      expect(values[7], ['a', 'b']);
    });

    test('carries entries for fields the tracker does not have (see #81)', () {
      // Documents today's behaviour rather than endorsing it. Switching
      // tracker leaves entries behind, and they are passed through. Redmine
      // drops them, so nothing wrong is created; issue #81 tightens this.
      final values = normalizeCustomFieldValues(
        fields: [_field(id: 1, name: 'Note')],
        entered: {1: 'kept', 99: 'from another tracker'},
      );

      expect(values.keys, [1, 99]);
    });
  });

  group('missingRequiredFields', () {
    test('names every unanswered required field, and no optional one', () {
      final fields = [
        _field(id: 1, name: 'Severity', required: true),
        _field(id: 2, name: 'Reported via', required: true),
        _field(id: 3, name: 'Note'),
      ];

      expect(missingRequiredFields(fields: fields, values: {1: 'High'}), [
        'Reported via',
      ]);
    });

    test('is empty when everything required is answered', () {
      final fields = [_field(id: 1, name: 'Severity', required: true)];

      expect(
        missingRequiredFields(fields: fields, values: {1: 'High'}),
        isEmpty,
      );
    });
  });

  group('nonNumericFields', () {
    test('rejects text in an int field', () {
      final fields = [_field(id: 1, name: 'Count', fieldFormat: 'int')];

      expect(nonNumericFields(fields: fields, values: {1: 'ten'}), ['Count']);
    });

    test('rejects a decimal in an int field but accepts it in a float', () {
      // int is stricter than float; conflating them lets "1.5" through as a
      // count and the server rejects it later, with a worse message.
      final intField = [_field(id: 1, name: 'Count', fieldFormat: 'int')];
      final floatField = [_field(id: 2, name: 'Depth', fieldFormat: 'float')];

      expect(nonNumericFields(fields: intField, values: {1: '1.5'}), ['Count']);
      expect(nonNumericFields(fields: floatField, values: {2: '1.5'}), isEmpty);
    });

    test('accepts negatives and leaves non-numeric formats alone', () {
      final fields = [
        _field(id: 1, name: 'Offset', fieldFormat: 'int'),
        _field(id: 2, name: 'Note'),
      ];

      expect(
        nonNumericFields(fields: fields, values: {1: '-3', 2: 'not a number'}),
        isEmpty,
      );
    });

    test('says nothing about a field that was left empty', () {
      // That is the required check's job; an empty optional number is fine.
      final fields = [_field(id: 1, name: 'Count', fieldFormat: 'int')];

      expect(nonNumericFields(fields: fields, values: const {}), isEmpty);
    });
  });
}
