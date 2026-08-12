import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/models/issue_document.dart';
import 'package:georeport/src/api/models/project_schema.dart';
import 'package:georeport/src/api/models/time_entry.dart';

void main() {
  test('parses the own-entries index page', () {
    final page = TimeEntriesPage.fromJson({
      'time_entries': [
        {
          'id': 1,
          'project': {'id': 4, 'name': 'Demo Reports'},
          'activity': {'id': 8, 'name': 'Planning'},
          'hours': 0.5,
          'spent_on': '2026-08-12',
          'comments': 'Smoke test',
          'issue': {'id': 32, 'subject': 'Broken streetlight'},
        },
      ],
      'total_count': 3,
      'total_hours': 4.25,
    });

    expect(page.totalCount, 3);
    expect(page.totalHours, 4.25);
    final entry = page.entries.single;
    expect(entry.hours, 0.5);
    expect(entry.activity?.name, 'Planning');
    expect(entry.issue?.id, 32);
    expect(entry.spentOn, DateTime(2026, 8, 12));
  });

  test('parses the schema time_entry section with the default activity', () {
    final schema = ProjectSchema.fromJson({
      'trackers': <Object>[],
      'custom_fields': <Object>[],
      'writable': <Object>[],
      'time_entry': {
        'can_log_time': true,
        'activities': [
          {'id': 8, 'name': 'Planning', 'is_default': false},
          {'id': 9, 'name': 'Execution', 'is_default': true},
        ],
      },
    });

    expect(schema.timeEntry.canLogTime, isTrue);
    expect(schema.timeEntry.activities, hasLength(2));
    expect(schema.timeEntry.defaultActivity?.id, 9);
  });

  test('a schema without the section degrades to no time entry support', () {
    final schema = ProjectSchema.fromJson(const {
      'trackers': <Object>[],
      'custom_fields': <Object>[],
      'writable': <Object>[],
    });

    expect(schema.timeEntry.canLogTime, isFalse);
    expect(schema.timeEntry.activities, isEmpty);
    expect(schema.timeEntry.defaultActivity, isNull);
  });

  test('the editing contract carries can_log_time, absent means false', () {
    expect(
      EditingContract.fromJson(const {'can_log_time': true}).canLogTime,
      isTrue,
    );
    expect(EditingContract.fromJson(const {}).canLogTime, isFalse);
  });
}
