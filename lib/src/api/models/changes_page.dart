import 'bundle.dart';
import 'geojson.dart';
import 'issue_summary.dart';

/// One page of `GET /gtt_sync/changes`: changed issues since the cursor,
/// the cursor for the next call, and optionally the caller's full visible
/// id set for deletion reconciliation.
class ChangesPage {
  const ChangesPage({
    required this.issues,
    required this.nextSince,
    required this.more,
    this.knownIds,
  });

  factory ChangesPage.fromJson(Map<String, dynamic> json) {
    final issues = <BundleIssue>[];
    final rawIssues = json['issues'];
    for (final entry in rawIssues is List ? rawIssues : const <Object>[]) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      // Feed entries are bundle summaries with the geometry inlined under a
      // `geometry` key; the key is absent for unplaced issues.
      final geometryJson = entry['geometry'] as Map<String, dynamic>?;
      issues.add(
        BundleIssue(
          summary: IssueSummary.fromJson(entry),
          geometry: IssueGeometry.fromJson(geometryJson),
          geometryJson: geometryJson,
        ),
      );
    }
    return ChangesPage(
      issues: issues,
      nextSince: json['next_since'] as String? ?? '',
      more: json['more'] == true,
      knownIds: switch (json['known_ids']) {
        final List<dynamic> ids =>
          ids.whereType<num>().map((id) => id.toInt()).toSet(),
        _ => null,
      },
    );
  }

  final List<BundleIssue> issues;
  final String nextSince;
  final bool more;
  final Set<int>? knownIds;
}
