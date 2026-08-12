import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/models/project_schema.dart';
import 'package:georeport/src/capture/issue_draft.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('builds the create payload with geometry, fields, and uploads', () {
    const draft = IssueDraft(
      projectId: 5,
      trackerId: 2,
      subject: 'Pothole',
      description: 'Deep one',
      location: LatLng(34.7, 135.5),
      customFieldValues: {
        1: 'High',
        3: ['a', 'b'],
      },
    );

    final payload = draft.toPayload([
      {'token': 't1', 'filename': 'a.jpg', 'content_type': 'image/jpeg'},
    ]);
    final issue = payload['issue'] as Map<String, dynamic>;

    expect(issue['project_id'], 5);
    expect(issue['tracker_id'], 2);
    expect(issue['subject'], 'Pothole');
    expect(issue['description'], 'Deep one');
    final geojson =
        json.decode(issue['geojson'] as String) as Map<String, dynamic>;
    final geometry = geojson['geometry'] as Map<String, dynamic>;
    expect(geometry['type'], 'Point');
    expect(geometry['coordinates'], [135.5, 34.7]);
    expect(issue['custom_fields'], [
      {'id': 1, 'value': 'High'},
      {
        'id': 3,
        'value': ['a', 'b'],
      },
    ]);
    expect((issue['uploads'] as List<dynamic>).single, {
      'token': 't1',
      'filename': 'a.jpg',
      'content_type': 'image/jpeg',
    });
  });

  test('omits optional parts that are unset', () {
    const draft = IssueDraft(projectId: 1, trackerId: 1, subject: 'Bare');
    final issue = draft.toPayload(const [])['issue'] as Map<String, dynamic>;

    expect(issue.containsKey('description'), isFalse);
    expect(issue.containsKey('geojson'), isFalse);
    expect(issue.containsKey('custom_fields'), isFalse);
    expect(issue.containsKey('uploads'), isFalse);
  });

  test('schema filters and orders custom fields per tracker', () {
    final schema = ProjectSchema.fromJson({
      'trackers': [
        {'id': 1, 'name': 'Task'},
        {'id': 2, 'name': 'Problem'},
      ],
      'custom_fields': [
        {
          'id': 1,
          'name': 'Severity',
          'field_format': 'list',
          'required': false,
          'multiple': false,
          'possible_values': ['Low', 'High'],
          'tracker_ids': [2],
        },
        {
          'id': 2,
          'name': 'Mandatory note',
          'field_format': 'string',
          'required': true,
          'multiple': false,
          'possible_values': <Object>[],
          'tracker_ids': [1, 2],
        },
        {
          'id': 3,
          'name': 'Everywhere',
          'field_format': 'string',
          'required': false,
          'multiple': false,
          'possible_values': <Object>[],
          'tracker_ids': <Object>[],
        },
      ],
      'writable': ['subject', 'tracker_id'],
    });

    final forTask = schema.fieldsForTracker(1);
    expect(forTask.map((field) => field.id), [2, 3]);
    expect(forTask.first.required, isTrue);

    final forProblem = schema.fieldsForTracker(2);
    expect(forProblem.map((field) => field.id), [2, 1, 3]);
    expect(schema.writable, contains('subject'));
  });
}
