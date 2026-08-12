import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/models/bundle.dart';
import 'package:georeport/src/api/models/changes_page.dart';
import 'package:georeport/src/api/models/issue_summary.dart';
import 'package:georeport/src/features/issues/issues_store.dart';

BundleIssue _issue(int id, {DateTime? due, String subject = 'x'}) {
  return BundleIssue(
    summary: IssueSummary(
      id: id,
      projectId: 1,
      subject: subject,
      statusId: 1,
      trackerId: 1,
      doneRatio: 0,
      lockVersion: 0,
      editable: true,
      dueDate: due,
    ),
  );
}

ChangesPage _page({
  List<Map<String, dynamic>> issues = const [],
  String nextSince = 'cursor-2',
  bool more = false,
  List<int>? knownIds,
}) {
  return ChangesPage.fromJson({
    'issues': issues,
    'next_since': nextSince,
    'more': more,
    'known_ids': ?knownIds,
  });
}

Map<String, dynamic> _feedIssue(int id, String subject) => {
  'id': id,
  'project_id': 1,
  'subject': subject,
  'status_id': 2,
  'tracker_id': 1,
  'done_ratio': 0,
  'lock_version': 1,
  'editable': true,
  'geometry': {
    'type': 'Point',
    'coordinates': [139.0, 35.0],
  },
};

void main() {
  test('sorts by due date with undated last, newest id first as tiebreak', () {
    final state = IssuesState(
      byId: {
        1: _issue(1),
        2: _issue(2, due: DateTime(2026, 8, 20)),
        3: _issue(3, due: DateTime(2026, 8, 15)),
        4: _issue(4),
      },
      projects: const [],
      cursor: 'c',
    );

    expect(state.sorted.map((issue) => issue.summary.id).toList(), [
      3,
      2,
      4,
      1,
    ]);
  });

  test('applyPage upserts changed issues and advances the cursor', () {
    final state = IssuesState(
      byId: {1: _issue(1, subject: 'old')},
      projects: const [],
      cursor: 'c1',
    );

    final next = state.applyPage(
      _page(issues: [_feedIssue(1, 'renamed'), _feedIssue(9, 'new')]),
    );

    expect(next.byId[1]!.summary.subject, 'renamed');
    expect(next.byId[1]!.isPlaced, isTrue);
    expect(next.byId[9]!.summary.subject, 'new');
    expect(next.cursor, 'cursor-2');
  });

  test('applyPage reconciles deletions from the known-id set', () {
    final state = IssuesState(
      byId: {1: _issue(1), 2: _issue(2), 3: _issue(3)},
      projects: const [],
      cursor: 'c1',
    );

    final next = state.applyPage(_page(knownIds: [1, 3]));

    expect(next.byId.keys.toSet(), {1, 3});
  });

  test('applyPage keeps the cursor when the page carries none', () {
    final state = IssuesState(byId: const {}, projects: const [], cursor: 'c1');
    expect(state.applyPage(_page(nextSince: '')).cursor, 'c1');
  });
}
