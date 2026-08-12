import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../api/gtt_sync_client.dart';
import '../../api/models/bundle.dart';
import '../../api/models/changes_page.dart';
import '../../connections/connection_manager.dart';
import '../../net/connectivity.dart';
import 'issue_providers.dart';
import 'issues_cache.dart';
import 'issues_state.dart';
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
  return IssuesCache(IssuesCache.fileFor(documents, connectionId));
});

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

  /// Captured at build time: every later write goes to THIS connection's
  /// file, even if the active connection changes mid-request.
  IssuesCache? _cache;

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
    final cache = _cache = await ref.watch(issuesCacheProvider.future);

    // Cache first: a restart — online or offline — starts from the last
    // known state, and the change feed catches up from its cursor (one
    // small request) instead of a full bundle reload.
    final cached = await cache?.load();
    if (cached != null) {
      final syncedAt = cached.syncedAt;
      if (syncedAt != null) {
        _restoreSyncTime(syncedAt);
      }
      // Assigned before scheduling, so the catch-up's state.value guard
      // sees the cached data instead of racing this build's completion.
      state = AsyncData(cached.state);
      // Catch up through the feed right away; the poll's own guards handle
      // offline and backgrounded states.
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
        final ChangesPage page;
        try {
          page = await client.changes(
            since: next.cursor,
            // The id set rides along once per refresh, on the first page.
            knownIds: pages == 0,
          );
        } on DioException catch (error) {
          final status = error.response?.statusCode ?? 0;
          if (status >= 400 && status < 500) {
            // The server rejected the cursor (a cache older than what the
            // feed retains): a fresh bundle replaces state and cursor, so
            // polls do not retry a dead cursor forever.
            await _reloadFromBundle(client);
            return;
          }
          rethrow;
        }
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
  /// sync (the next one retries anyway). Writes go through the cache
  /// captured at build time, so they stay bound to their connection.
  Future<void> _persist(IssuesState state) async {
    try {
      await _cache?.save(state, syncedAt: DateTime.now());
    } on Exception catch (error) {
      debugPrint('Issues cache write failed (ignored): $error');
    }
  }

  /// Replaces state and cursor from a fresh bundle: the recovery for a
  /// cursor the server no longer accepts.
  Future<void> _reloadFromBundle(GttSyncClient client) async {
    final cursor = DateTime.now().toUtc().toIso8601String();
    final bundle = await client.bundle();
    if (!ref.mounted) {
      return;
    }
    final fresh = IssuesState(
      byId: {for (final issue in bundle.issues) issue.summary.id: issue},
      projects: bundle.projects,
      cursor: cursor,
    );
    state = AsyncData(fresh);
    _recordSync(healthy: true);
    await _persist(fresh);
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
