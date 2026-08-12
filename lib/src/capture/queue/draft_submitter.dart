import 'package:dio/dio.dart';

import '../../api/issue_submit_api.dart';
import '../image_shrink.dart';
import 'draft_store.dart';
import 'queued_draft.dart';

/// Outcome of one submission attempt.
sealed class SubmitResult {
  const SubmitResult();
}

/// The issue exists on the server; the entry can leave the queue.
class SubmitCreated extends SubmitResult {
  const SubmitCreated(this.issueId);
  final int issueId;
}

/// A transient failure; [draft] holds the persisted retry bookkeeping.
class SubmitRetryLater extends SubmitResult {
  const SubmitRetryLater(this.draft);
  final QueuedDraft draft;
}

/// The server rejected the draft permanently; only the user can resolve it.
class SubmitFailed extends SubmitResult {
  const SubmitFailed(this.draft);
  final QueuedDraft draft;
}

/// Clock-skew allowance when asking the server whether an interrupted
/// create actually went through: the dedup window starts this much before
/// the entry was queued. Kept small so an identical subject submitted
/// legitimately minutes earlier is not mistaken for this entry.
const _dedupSkew = Duration(minutes: 2);

/// Drives one queued draft toward a created issue. Stateless itself: every
/// transition is persisted through the store before the next side effect,
/// so the app can die at any point and resume where it left off.
///
/// Exactly-once creation: the entry is marked [QueuedDraftState.creating]
/// and flushed to disk BEFORE the create request leaves the device. A retry
/// of an entry found in that state first asks the server whether a matching
/// issue (same author, project, subject, created since the entry was queued)
/// already exists, and adopts it instead of creating a duplicate.
class DraftSubmitter {
  DraftSubmitter({
    required this._api,
    required this._store,
    this._shrink = shrinkForUpload,
  });

  final IssueSubmitApi _api;
  final DraftStore _store;
  final ImageShrinker _shrink;

  Future<SubmitResult> process(QueuedDraft draft) async {
    var current = draft;
    try {
      if (current.state == QueuedDraftState.creating) {
        final existing = await _findExisting(current);
        if (existing != null) {
          return SubmitCreated(existing);
        }
        // Provably not created; safe to continue as a normal attempt.
      }
      for (var i = 0; i < current.photos.length; i++) {
        final photo = current.photos[i];
        if (photo.token != null) {
          continue;
        }
        final bytes = await _store.readPhoto(current, photo);
        final shrunk = await _shrink(bytes, photo.contentType);
        final token = await _api.uploadFile(shrunk, photo.filename);
        final photos = [...current.photos];
        photos[i] = photo.withToken(token);
        current = current.copyWith(photos: photos);
        await _store.save(current);
      }
      current = current.copyWith(state: QueuedDraftState.creating);
      await _store.save(current);
      return SubmitCreated(await _api.createIssue(current.payload()));
    } on DioException catch (error) {
      return _classify(current, error);
    }
  }

  Future<int?> _findExisting(QueuedDraft draft) async {
    final candidates = await _api.myIssuesCreatedSince(
      projectId: draft.projectId,
      since: draft.createdAt.subtract(_dedupSkew),
    );
    for (final candidate in candidates) {
      if (candidate.subject == draft.subject) {
        return candidate.id;
      }
    }
    return null;
  }

  Future<SubmitResult> _classify(QueuedDraft draft, DioException error) async {
    // The request provably never reached the server, so the create (if we
    // got that far) did not happen: back to pending, no dedup check needed.
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return SubmitRetryLater(
        await _retryLater(draft, error, provenUnsent: true),
      );
    }
    final status = error.response?.statusCode;
    if (status == 422) {
      final errors = _validationErrors(error);
      // A stale or invalid attachment token (Redmine purges unattached
      // uploads): drop the tokens and upload again next round.
      if (errors.any((message) => message.toLowerCase().contains('attach'))) {
        final reset = draft.copyWith(
          photos: [for (final photo in draft.photos) photo.withToken(null)],
          state: QueuedDraftState.pending,
        );
        return SubmitRetryLater(
          await _retryLater(reset, error, provenUnsent: true),
        );
      }
      final failed = draft.copyWith(
        state: QueuedDraftState.failed,
        lastError: errors.isEmpty ? 'HTTP 422' : errors.join('; '),
      );
      await _store.save(failed);
      return SubmitFailed(failed);
    }
    // Everything else (timeouts after sending, 5xx, lost responses) leaves
    // the outcome unknown; the state on disk decides whether the next round
    // runs the dedup check first.
    return SubmitRetryLater(await _retryLater(draft, error));
  }

  Future<QueuedDraft> _retryLater(
    QueuedDraft draft,
    DioException error, {
    bool provenUnsent = false,
  }) async {
    final attempts = draft.attempts + 1;
    final updated = draft.copyWith(
      state: provenUnsent ? QueuedDraftState.pending : draft.state,
      attempts: attempts,
      nextAttemptAt: DateTime.now().toUtc().add(retryDelay(attempts)),
      lastError: error.message ?? error.type.name,
    );
    await _store.save(updated);
    return updated;
  }

  static List<String> _validationErrors(DioException error) {
    final data = error.response?.data;
    final errors = data is Map<String, dynamic> ? data['errors'] : null;
    return errors is List ? errors.whereType<String>().toList() : const [];
  }
}

/// Exponential backoff: 30s, 1m, 2m, ... capped at 15 minutes.
Duration retryDelay(int attempts) {
  final seconds = 30 * (1 << (attempts - 1).clamp(0, 5));
  return Duration(seconds: seconds.clamp(30, 900));
}
