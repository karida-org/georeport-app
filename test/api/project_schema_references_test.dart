import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/models/project_schema.dart';

void main() {
  ProjectSchema parse(Object? references) => ProjectSchema.fromJson({
    'trackers': <dynamic>[],
    'custom_fields': <dynamic>[],
    'writable': <dynamic>[],
    'references': references,
  });

  test('reference options are parsed per field', () {
    final schema = parse({
      'priority_id': [
        {'id': 3, 'name': 'High'},
        {'id': 4, 'name': 'Urgent'},
      ],
      'category_id': <dynamic>[],
    });
    expect(schema.references['priority_id']!.map((o) => o.name), [
      'High',
      'Urgent',
    ]);
    expect(schema.references['category_id'], isEmpty);
  });

  test('unusable entries are dropped rather than offered', () {
    final schema = parse({
      'assigned_to_id': [
        {'id': 1, 'name': 'Site Administrator'},
        {'id': 0, 'name': 'No id'},
        {'id': 7, 'name': ''},
        'not a map',
      ],
    });
    expect(
      schema.references['assigned_to_id']!.single.name,
      'Site Administrator',
    );
  });

  test('an unexpected shape yields no references instead of throwing', () {
    expect(parse('nonsense').references, isEmpty);
    expect(parse(null).references, isEmpty);
    expect(
      parse({'priority_id': 'nonsense'}).references['priority_id'],
      isEmpty,
    );
  });
}
