import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/bundle.dart';
import '../../api/models/changes_page.dart';
import '../../net/connectivity.dart';
import 'issue_providers.dart';
import 'sync_status.dart';

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

  /// How often the change feed is polled while the store is alive. The feed
  /// is cursor-based and usually returns an empty page, so keeping the map
  /// and list fresh costs one small request per interval.
  static const autoRefreshInterval = Duration(minutes: 1);

  bool _refreshing = false;
  bool _disposed = false;

  @override
  Future<IssuesState> build() async {
    _disposed = false;
    final timer = Timer.periodic(autoRefreshInterval, (_) => _autoRefresh());
    ref.onDispose(() {
      _disposed = true;
      timer.cancel();
    });
    // Back online: sync right away instead of waiting out the interval.
    ref.listen(isOnlineProvider, (wasOnline, online) {
      if (wasOnline == false && online) {
        _autoRefresh();
      }
    });
    final client = ref.watch(activeClientProvider);
    // The cursor is taken before the bundle loads: the feed is at-least-once
    // and applied idempotently, so overlap is safe while a gap would not be.
    final cursor = DateTime.now().toUtc().toIso8601String();
    final bundle = await client.bundle();
    _recordSync(healthy: true);
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
    try {
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
      _recordSync(healthy: true);
    } on Exception {
      _recordSync(healthy: false);
      rethrow;
    }
  }

  /// The periodic poll: quiet by design — the shown data stays on failure,
  /// and the outcome lands in the sync status for the shell's menu. An
  /// offline device skips the attempt entirely (no battery spent on doomed
  /// requests, and no scary failure state for an expected situation).
  Future<void> _autoRefresh() async {
    if (_refreshing || state.value == null || !ref.read(isOnlineProvider)) {
      return;
    }
    _refreshing = true;
    try {
      await refresh();
    } on Exception catch (error) {
      debugPrint('Issues auto-refresh failed: $error');
    } finally {
      _refreshing = false;
    }
  }

  /// Records into a foreign provider, which is not allowed synchronously
  /// during build; the microtask defers past initialization, and the
  /// dispose guard covers a store torn down in the meantime.
  void _recordSync({required bool healthy}) {
    Future.microtask(() {
      if (_disposed) {
        return;
      }
      final status = ref.read(syncStatusProvider.notifier);
      healthy ? status.recordSuccess(DateTime.now()) : status.recordFailure();
    });
  }
}
