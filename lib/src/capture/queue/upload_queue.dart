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
    // Entries left over from a previous run start moving right away.
    unawaited(Future.microtask(process));
    return store.list();
  }

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
      case SubmitFailed(:final draft):
        await store.remove(draft.id);
        await _refresh();
        throw QueueSubmitException(draft.lastError ?? 'Rejected');
      case null:
        return null;
    }
  }

  /// Processes every due entry of the active connection, oldest first.
  Future<void> process() async {
    final store = _store;
    if (store == null || _processing) {
      return;
    }
    _processing = true;
    try {
      final activeId = ref
          .read(connectionManagerProvider)
          .value
          ?.active
          ?.connection
          .id;
      if (activeId == null) {
        return;
      }
      final now = DateTime.now().toUtc();
      for (final entry in await store.list()) {
        if (entry.connectionId != activeId ||
            entry.state == QueuedDraftState.failed ||
            (entry.nextAttemptAt?.isAfter(now) ?? false)) {
          continue;
        }
        await _processOne(entry, ownsLock: true);
      }
    } finally {
      _processing = false;
    }
    _scheduleNextRun();
  }

  /// Manual retry from the outbox UI; also revives failed entries.
  Future<void> retry(String id) async {
    final store = _store;
    if (store == null) {
      return;
    }
    final entry = (await store.list()).where((d) => d.id == id).firstOrNull;
    if (entry == null) {
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
        ref.invalidate(issuesProvider);
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
    final entries = state.value ?? const [];
    final due = [
      for (final entry in entries)
        if (entry.state != QueuedDraftState.failed)
          entry.nextAttemptAt ?? DateTime.now().toUtc(),
    ];
    if (due.isEmpty) {
      return;
    }
    due.sort();
    var wait = due.first.difference(DateTime.now().toUtc());
    if (wait.isNegative) {
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
