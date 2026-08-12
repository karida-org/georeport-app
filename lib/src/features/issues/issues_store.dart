import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../api/models/bundle.dart';
import '../../api/models/changes_page.dart';
import '../../connections/connection_manager.dart';
import '../../net/connectivity.dart';
import 'issue_providers.dart';
import 'issues_cache.dart';
import 'sync_status.dart';

/// The on-disk cache for the active connection's issues; null while nothing
/// is connected. One file per connection, so switching instances never
/// shows another instance's data.
final issuesCacheProvider = FutureProvider.autoDispose<IssuesCache?>((
  ref,
) async {
  final connectionId = ref.watch(
    connectionManagerProvider.select(
      (state) => state.value?.active?.connection.id,
    ),
  );
  if (connectionId == null) {
    return null;
  }
  final documents = await getApplicationDocumentsDirectory();
  return IssuesCache(File('${documents.path}/issues-$connectionId.json'));
});

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

  @override
  Future<IssuesState> build() async {
    final timer = Timer.periodic(autoRefreshInterval, (_) => _autoRefresh());
    // Coming back to the app is the moment fresh data matters most.
    final lifecycle = AppLifecycleListener(onResume: _autoRefresh);
    ref.onDispose(() {
      timer.cancel();
      lifecycle.dispose();
    });
    // Back online: sync right away instead of waiting out the interval.
    ref.listen(isOnlineProvider, (wasOnline, online) {
      if (wasOnline == false && online) {
        _autoRefresh();
      }
    });
    final client = ref.watch(activeClientProvider);
    final cache = await ref.watch(issuesCacheProvider.future);

    // Cache first: a restart — online or offline — starts from the last
    // known state, and the change feed catches up from its cursor (one
    // small request) instead of a full bundle reload.
    final cached = await cache?.load();
    if (cached != null) {
      final syncedAt = cached.syncedAt;
      if (syncedAt != null) {
        _restoreSyncTime(syncedAt);
      }
      // Catch up through the feed as soon as this build completes; the
      // poll's own guards handle offline and backgrounded states.
      unawaited(Future.microtask(_autoRefresh));
      return cached.state;
    }

    // The cursor is taken before the bundle loads: the feed is at-least-once
    // and applied idempotently, so overlap is safe while a gap would not be.
    final cursor = DateTime.now().toUtc().toIso8601String();
    final Bundle bundle;
    try {
      bundle = await client.bundle();
    } on Exception {
      // The store surfaces AsyncError; the menu's status must agree.
      _recordSync(healthy: false);
      rethrow;
    }
    _recordSync(healthy: true);
    final fresh = IssuesState(
      byId: {for (final issue in bundle.issues) issue.summary.id: issue},
      projects: bundle.projects,
      cursor: cursor,
    );
    await _persist(fresh);
    return fresh;
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
      // The store can be torn down while a page is in flight (switching
      // instances); its result is then nobody's business.
      if (!ref.mounted) {
        return;
      }
      state = AsyncData(next);
      _recordSync(healthy: true);
      await _persist(next);
    } on Exception {
      _recordSync(healthy: false);
      rethrow;
    }
  }

  /// Best effort: a failed cache write must never take down a successful
  /// sync (the next one retries anyway).
  Future<void> _persist(IssuesState state) async {
    try {
      final cache = await ref.read(issuesCacheProvider.future);
      await cache?.save(state, syncedAt: DateTime.now());
    } on Exception catch (error) {
      debugPrint('Issues cache write failed (ignored): $error');
    }
  }

  /// Data served from disk shows how old it is: the cached last-sync time
  /// lands in the menu until a live sync updates it.
  void _restoreSyncTime(DateTime syncedAt) {
    Future.microtask(() {
      if (!ref.mounted) {
        return;
      }
      final status = ref.read(syncStatusProvider);
      // Never move an already-live status backwards.
      if (status.lastSyncAt == null || status.lastSyncAt!.isBefore(syncedAt)) {
        ref.read(syncStatusProvider.notifier).recordSuccess(syncedAt);
      }
    });
  }

  /// The periodic poll: quiet by design — the shown data stays on failure,
  /// and the outcome lands in the sync status for the shell's menu. An
  /// offline device skips the attempt entirely (no battery spent on doomed
  /// requests, and no scary failure state for an expected situation), as
  /// does a backgrounded app.
  Future<void> _autoRefresh() async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (_refreshing ||
        !ref.mounted ||
        state.value == null ||
        !ref.read(isOnlineProvider) ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    _refreshing = true;
    try {
      await refresh();
      // A fire-and-forget timer callback has nobody above it to catch, so
      // Error must not escape either (an unhandled async error otherwise).
      // ignore: avoid_catches_without_on_clauses
    } catch (error, stack) {
      debugPrint('Issues auto-refresh failed: $error\n$stack');
    } finally {
      _refreshing = false;
    }
  }

  /// Records into a foreign provider, which is not allowed synchronously
  /// during build; the microtask defers past initialization, and the
  /// mounted check covers a store torn down in the meantime.
  void _recordSync({required bool healthy}) {
    Future.microtask(() {
      if (!ref.mounted) {
        return;
      }
      final status = ref.read(syncStatusProvider.notifier);
      healthy ? status.recordSuccess(DateTime.now()) : status.recordFailure();
    });
  }
}
