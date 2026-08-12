import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/models/bundle.dart';
import 'package:georeport/src/api/models/geojson.dart';
import 'package:georeport/src/api/models/issue_summary.dart';
import 'package:georeport/src/features/issues/issues_cache.dart';
import 'package:georeport/src/features/issues/issues_store.dart';

void main() {
  late Directory temp;
  late IssuesCache cache;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('issues-cache-test');
    cache = IssuesCache(File('${temp.path}/issues.json'));
  });

  tearDown(() => temp.delete(recursive: true));

  IssuesState sampleState() {
    const geometryJson = {
      'type': 'Point',
      'coordinates': [135.2, 34.7],
    };
    final placed = BundleIssue(
      summary: IssueSummary.fromJson({
        'id': 32,
        'project_id': 1,
        'subject': 'Broken streetlight',
        'status_id': 3,
        'tracker_id': 1,
        'lock_version': 5,
        'assigned_to': 'Site Administrator',
        'due_date': '2026-07-09',
      }),
      geometry: IssueGeometry.fromJson(geometryJson),
      geometryJson: geometryJson,
    );
    final unplaced = BundleIssue(
      summary: IssueSummary.fromJson({
        'id': 69,
        'project_id': 2,
        'subject': 'Urgent site access',
        'status_id': 2,
        'tracker_id': 3,
      }),
    );
    return IssuesState(
      byId: {32: placed, 69: unplaced},
      projects: const [
        BundleProject(
          id: 1,
          identifier: 'demo',
          name: 'Demo Reports',
          hasBoundary: true,
        ),
      ],
      cursor: '2026-08-13T00:00:00.000Z',
    );
  }

  test('a saved state comes back whole', () async {
    final syncedAt = DateTime.utc(2026, 8, 13, 1, 2, 3);
    await cache.save(sampleState(), syncedAt: syncedAt);

    final loaded = await cache.load();
    expect(loaded, isNotNull);
    expect(loaded!.syncedAt, syncedAt);
    final state = loaded.state;
    expect(state.cursor, '2026-08-13T00:00:00.000Z');
    expect(state.projects.single.name, 'Demo Reports');
    expect(state.projects.single.hasBoundary, isTrue);
    expect(state.byId.keys, containsAll([32, 69]));

    final placed = state.byId[32]!;
    expect(placed.summary.subject, 'Broken streetlight');
    expect(placed.summary.lockVersion, 5);
    expect(placed.summary.assignedTo, 'Site Administrator');
    expect(placed.summary.dueDate, DateTime.parse('2026-07-09'));
    expect(placed.isPlaced, isTrue);
    expect(placed.geometryJson?['type'], 'Point');
    expect(state.byId[69]!.isPlaced, isFalse);
  });

  test('a missing file loads as null', () async {
    expect(await cache.load(), isNull);
  });

  test('a corrupt file loads as null instead of failing the launch', () async {
    await File('${temp.path}/issues.json').writeAsString('not json{');
    expect(await cache.load(), isNull);
  });

  test('clear removes the file', () async {
    await cache.save(sampleState(), syncedAt: DateTime.now());
    await cache.clear();
    expect(await cache.load(), isNull);
  });
}
