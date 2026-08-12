import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/models/bundle.dart';
import 'package:georeport/src/api/models/geojson.dart';
import 'package:georeport/src/api/models/issue_summary.dart';
import 'package:georeport/src/features/home/today_providers.dart';
import 'package:georeport/src/nav/maps_handoff.dart';
import 'package:latlong2/latlong.dart';

BundleIssue issue({required int id, String? assignedTo, DateTime? dueDate}) =>
    BundleIssue(
      summary: IssueSummary.fromJson({
        'id': id,
        'project_id': 1,
        'subject': 'Issue $id',
        'status_id': 1,
        'tracker_id': 1,
        'assigned_to': ?assignedTo,
        if (dueDate != null)
          'due_date': dueDate.toIso8601String().split('T').first,
      }),
    );

void main() {
  final today = DateTime(2026, 8, 12, 14, 30);

  test('selects only my issues due today or overdue, ordered by due date', () {
    final result = todayIssues(
      [
        issue(id: 1, assignedTo: 'Me', dueDate: DateTime(2026, 8, 13)),
        issue(id: 2, assignedTo: 'Me', dueDate: DateTime(2026, 8, 12)),
        issue(id: 3, assignedTo: 'Me', dueDate: DateTime(2026, 8, 1)),
        issue(
          id: 4,
          assignedTo: 'Someone else',
          dueDate: DateTime(2026, 8, 12),
        ),
        issue(id: 5, assignedTo: 'Me'), // no due date
      ],
      assigneeDisplayName: 'Me',
      today: today,
    );

    expect([for (final i in result) i.summary.id], [3, 2]);
  });

  test('an unknown identity yields an empty plate, not everything', () {
    final result = todayIssues(
      [issue(id: 1, assignedTo: 'Me', dueDate: DateTime(2026, 8, 12))],
      assigneeDisplayName: null,
      today: today,
    );
    expect(result, isEmpty);
  });

  group('maps handoff', () {
    test('representative point per geometry type', () {
      const point = LatLng(34.7, 135.2);
      expect(representativePoint(const PointGeometry([point])), point);
      expect(
        representativePoint(
          const LineGeometry([
            [point, LatLng(34.8, 135.3)],
          ]),
        ),
        point,
      );
      expect(
        representativePoint(
          const PolygonGeometry([
            [point, LatLng(34.8, 135.3), LatLng(34.9, 135.4)],
          ]),
        ),
        point,
      );
      expect(representativePoint(null), isNull);
    });

    test('platform directions URLs', () {
      const destination = LatLng(34.6864, 135.1959);
      expect(
        directionsUrl(destination, apple: true).toString(),
        'https://maps.apple.com/?daddr=34.6864,135.1959&dirflg=d',
      );
      expect(
        directionsUrl(destination, apple: false).toString(),
        'https://www.google.com/maps/dir/?api=1&destination=34.6864,135.1959',
      );
    });
  });
}
