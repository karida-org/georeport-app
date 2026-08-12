import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../connections/connection_manager.dart';
import '../../features/issues/issues_store.dart';
import '../issue_draft.dart';
import 'draft_store.dart';
import 'draft_submitter.dart';
import 'queued_draft.dart';

/// The on-disk outbox in the app documents directory.
final draftStoreProvider = FutureProvider<DraftStore>((ref) async {
  final documents = await getApplicationDocumentsDirectory();
  return DraftStore(Directory('${documents.path}/outbox'));
});

/// Connectivity changes; a provider seam so tests can inject a quiet stream.
final connectivityChangesProvider = StreamProvider<List<ConnectivityResult>>(
  (ref) => Connectivity().onConnectivityChanged,
);

final uploadQueueProvider =
    AsyncNotifierProvider<UploadQueue, List<QueuedDraft>>(UploadQueue.new);

/// Outbox entries belonging to the active connection: the slice the UI
/// shows and the queue processes. Entries of other saved connections wait
/// on disk until their connection becomes active again.
final activeOutboxEntriesProvider = Provider.autoDispose<List<QueuedDraft>>((
  ref,
) {
  final activeId = ref
      .watch(connectionManagerProvider)
      .value
      ?.active
      ?.connection
      .id;
  final entries = ref.watch(uploadQueueProvider).value ?? const [];
  return [
    for (final entry in entries)
      if (entry.connectionId == activeId) entry,
  ];
});

/// Owns the outbox lifecycle: entries enter on submit, get processed with
/// backoff whenever the app starts, connectivity returns, or the user asks,
/// and leave once the issue exists on the server.
class UploadQueue extends AsyncNotifier<List<QueuedDraft>> {
  DraftStore? _store;
  bool _processing = false;
  Timer? _timer;

  @override
  Future<List<QueuedDraft>> build() async {
    final store = await ref.watch(draftStoreProvider.future);
    _store = store;
    ref.listen(connectivityChangesProvider, (previous, next) {
      final results = next.value;
      if (results != null &&
          results.any((result) => result != ConnectivityResult.none)) {
        unawaited(process());
      }
    });
    ref.onDispose(() => _timer?.cancel());
    await store.sweepOrphans();
    final initial = await store.list();
    // Entries left over from a previous run start moving right away. An
    // event-queue task runs after Riverpod has committed the build result,
    // so process() never touches state mid-build.
    unawaited(Future(process));
    return initial;
  }

  String? get _activeConnectionId =>
      ref.read(connectionManagerProvider).value?.active?.connection.id;

  /// Submits a fresh draft: persist first, then try immediately.
  /// Returns the new issue id when it went through right now, or null when
  /// the entry stays parked in the outbox for automatic retry. Permanent
  /// rejections throw with the server's message and leave nothing queued,
  /// so the capture form keeps the draft for the user to fix.
  Future<int?> submit(IssueDraft draft) async {
    final store = _store;
    final active = ref.read(connectionManagerProvider).value?.active;
    if (store == null || active == null) {
      throw StateError('Not connected');
    }
    final entry = await store.add(
      QueuedDraft(
        id: DraftStore.newId(),
        connectionId: active.connection.id,
        createdAt: DateTime.now().toUtc(),
        projectId: draft.projectId,
        trackerId: draft.trackerId,
        subject: draft.subject,
        description: draft.description,
        location: draft.location,
        customFieldValues: draft.customFieldValues,
      ),
      draft.photos,
    );
    await _refresh();
    final result = await _processOne(entry);
    switch (result) {
      case SubmitCreated(:final issueId):
        return issueId;
      case SubmitRetryLater():
        _scheduleNextRun();
        return null;
      case SubmitFailed(draft: final rejected):
        await store.remove(rejected.id);
        await _refresh();
        throw QueueSubmitException(rejected.lastError ?? 'Rejected');
      case null:
        // Another pass holds the lock; it works from an older snapshot, so
        // make sure this new entry gets a timer of its own.
        _scheduleNextRun();
        return null;
    }
  }

  /// Processes every due entry of the active connection, oldest first.
  /// One bad entry never blocks the rest, and the next run is always
  /// scheduled, whatever happens.
  Future<void> process() async {
    final store = _store;
    if (store == null || _processing) {
      return;
    }
    _processing = true;
    var createdAny = false;
    try {
      final activeId = _activeConnectionId;
      if (activeId == null) {
        return;
      }
      final now = DateTime.now().toUtc();
      for (final snapshot in await store.list()) {
        if (snapshot.connectionId != activeId ||
            snapshot.state == QueuedDraftState.failed ||
            (snapshot.nextAttemptAt?.isAfter(now) ?? false)) {
          continue;
        }
        // The user can discard an entry from the outbox while this pass
        // runs; one stat per entry honors that without rescanning the
        // whole store.
        if (!store.exists(snapshot.id)) {
          continue;
        }
        try {
          final result = await _processOne(
            snapshot,
            ownsLock: true,
            invalidateIssues: false,
          );
          createdAny = createdAny || result is SubmitCreated;
          // The submitter classifies everything it can; anything that still
          // escapes must not take the rest of the queue down with it.
          // ignore: avoid_catches_without_on_clauses
        } catch (_) {
          continue;
        }
      }
    } finally {
      _processing = false;
      if (createdAny) {
        ref.invalidate(issuesProvider);
      }
      _scheduleNextRun();
    }
  }

  /// Manual retry from the outbox UI; also revives failed entries.
  Future<void> retry(String id) async {
    final store = _store;
    if (store == null) {
      return;
    }
    final entry = (await store.list()).where((d) => d.id == id).firstOrNull;
    // Never submit a draft to a connection it was not captured for.
    if (entry == null || entry.connectionId != _activeConnectionId) {
      return;
    }
    final revived = entry.state == QueuedDraftState.failed
        ? entry.copyWith(
            state: QueuedDraftState.pending,
            clearNextAttempt: true,
            clearError: true,
          )
        : entry.copyWith(clearNextAttempt: true);
    await store.save(revived);
    await _refresh();
    await _processOne(revived);
    _scheduleNextRun();
  }

  Future<void> discard(String id) async {
    await _store?.remove(id);
    await _refresh();
  }

  Future<SubmitResult?> _processOne(
    QueuedDraft entry, {
    bool ownsLock = false,
    bool invalidateIssues = true,
  }) async {
    final store = _store;
    final client = ref.read(connectionManagerProvider).value?.active?.client;
    if (store == null || client == null) {
      return null;
    }
    if (!ownsLock) {
      if (_processing) {
        return null;
      }
      _processing = true;
    }
    try {
      final submitter = DraftSubmitter(api: client, store: store);
      final result = await submitter.process(entry);
      if (result is SubmitCreated) {
        await store.remove(entry.id);
        if (invalidateIssues) {
          ref.invalidate(issuesProvider);
        }
      }
      await _refresh();
      return result;
    } finally {
      if (!ownsLock) {
        _processing = false;
      }
    }
  }

  Future<void> _refresh() async {
    final store = _store;
    if (store != null) {
      state = AsyncData(await store.list());
    }
  }

  void _scheduleNextRun() {
    _timer?.cancel();
    final activeId = _activeConnectionId;
    final entries = state.value ?? const [];
    final due = [
      for (final entry in entries)
        if (entry.state != QueuedDraftState.failed &&
            entry.connectionId == activeId)
          entry.nextAttemptAt ?? DateTime.now().toUtc(),
    ];
    if (due.isEmpty) {
      return;
    }
    due.sort();
    var wait = due.first.difference(DateTime.now().toUtc());
    if (wait < const Duration(seconds: 5)) {
      wait = const Duration(seconds: 5);
    }
    _timer = Timer(wait, () => unawaited(process()));
  }
}

/// A permanent server-side rejection of a submitted draft.
class QueueSubmitException implements Exception {
  const QueueSubmitException(this.message);
  final String message;

  @override
  String toString() => message;
}
