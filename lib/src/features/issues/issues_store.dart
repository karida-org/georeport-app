import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/bundle.dart';
import '../../api/models/changes_page.dart';
import 'issue_providers.dart';

/// The issues held in memory for the active connection, keyed by id, plus
/// the change-feed cursor that keeps them fresh. Pure data: applying a feed
/// page returns a new state, which keeps the sync logic unit-testable.
class IssuesState {
  const IssuesState({
    required this.byId,
    required this.projects,
    required this.cursor,
  });

  final Map<int, BundleIssue> byId;
  final List<BundleProject> projects;
  final String cursor;

  /// Due date first (undated last), newest id as the tiebreaker.
  List<BundleIssue> get sorted {
    final issues = byId.values.toList();
    issues.sort((a, b) {
      final aDue = a.summary.dueDate;
      final bDue = b.summary.dueDate;
      if (aDue != null && bDue != null && !aDue.isAtSameMomentAs(bDue)) {
        return aDue.compareTo(bDue);
      }
      if ((aDue == null) != (bDue == null)) {
        return aDue == null ? 1 : -1;
      }
      return b.summary.id.compareTo(a.summary.id);
    });
    return issues;
  }

  /// Upserts the page's issues, reconciles deletions when the page carries
  /// the known-id set, and advances the cursor.
  IssuesState applyPage(ChangesPage page) {
    final next = Map<int, BundleIssue>.of(byId);
    for (final issue in page.issues) {
      next[issue.summary.id] = issue;
    }
    final known = page.knownIds;
    if (known != null) {
      next.removeWhere((id, _) => !known.contains(id));
    }
    return IssuesState(
      byId: next,
      projects: projects,
      cursor: page.nextSince.isEmpty ? cursor : page.nextSince,
    );
  }
}

final issuesProvider =
    AsyncNotifierProvider.autoDispose<IssuesNotifier, IssuesState>(
      IssuesNotifier.new,
    );

class IssuesNotifier extends AsyncNotifier<IssuesState> {
  static const _maxFeedPages = 20;

  @override
  Future<IssuesState> build() async {
    final client = ref.watch(activeClientProvider);
    // The cursor is taken before the bundle loads: the feed is at-least-once
    // and applied idempotently, so overlap is safe while a gap would not be.
    final cursor = DateTime.now().toUtc().toIso8601String();
    final bundle = await client.bundle();
    return IssuesState(
      byId: {for (final issue in bundle.issues) issue.summary.id: issue},
      projects: bundle.projects,
      cursor: cursor,
    );
  }

  /// Incremental refresh through the change feed. Throws on failure so a
  /// pull-to-refresh can surface the problem while the shown data stays.
  Future<void> refresh() async {
    final current = state.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    final client = ref.read(activeClientProvider);
    var next = current;
    var pages = 0;
    while (true) {
      final page = await client.changes(
        since: next.cursor,
        // The id set rides along once per refresh, on the first page.
        knownIds: pages == 0,
      );
      next = next.applyPage(page);
      pages += 1;
      if (!page.more || pages >= _maxFeedPages) {
        break;
      }
    }
    state = AsyncData(next);
  }
}
