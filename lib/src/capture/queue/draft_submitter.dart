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
/// The dedup probe's answer, so "no issue found" is distinguishable from
/// "the probe itself could not run".
class DraftIssueLookup {
  const DraftIssueLookup(this.issueId);

  final int? issueId;
}

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
        // The dedup probe uses stock /issues.json, OUTSIDE this contract, so
        // a narrow OAuth scope or role can refuse it. A refused probe says
        // nothing about whether the issue exists, so it must not be
        // classified like a failed create: retry later and ask again.
        final DraftIssueLookup existing;
        try {
          existing = DraftIssueLookup(await _findExisting(current));
        } on DioException catch (error) {
          return SubmitRetryLater(
            await _retryLater(current, error, provenUnsent: false),
          );
        }
        if (existing.issueId != null) {
          await _store.claimIssue(existing.issueId!);
          return SubmitCreated(existing.issueId!);
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
      final issueId = await _api.createIssue(current.payload());
      await _store.claimIssue(issueId);
      return SubmitCreated(issueId);
    } on DioException catch (error) {
      return _classify(current, error);
      // A non-network failure (missing photo file, undecodable image,
      // malformed server payload) cannot heal through retries; leaving it
      // due would poison the queue and stall every later entry.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      final failed = current.copyWith(
        state: QueuedDraftState.failed,
        lastError: '$error',
      );
      await _store.save(failed);
      return SubmitFailed(failed);
    }
  }

  Future<int?> _findExisting(QueuedDraft draft) async {
    final candidates = await _api.myIssuesCreatedSince(
      projectId: draft.projectId,
      since: draft.createdAt.subtract(_dedupSkew),
    );
    // Ids this device already created or adopted are spoken for; without
    // this, two same-subject drafts could both resolve to one issue.
    final claimed = await _store.claimedIssues();
    for (final candidate in candidates) {
      if (candidate.subject == draft.subject &&
          !claimed.contains(candidate.id)) {
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
      // A 422 on a payload that carries upload tokens may just mean the
      // tokens went stale (Redmine purges unattached uploads). Validation
      // messages are localized, so the condition is detected structurally:
      // reset the tokens and retry once with fresh uploads; a second 422
      // is a real rejection.
      final hasTokens = draft.photos.any((photo) => photo.token != null);
      if (hasTokens && draft.tokenResets == 0) {
        final reset = draft.copyWith(
          photos: [for (final photo in draft.photos) photo.withToken(null)],
          tokenResets: 1,
          state: QueuedDraftState.pending,
        );
        return SubmitRetryLater(
          await _retryLater(reset, error, provenUnsent: true),
        );
      }
      return _fail(draft, error);
    }
    // Other non-retryable client errors: permission lost (403), project
    // gone (404), malformed request (400). Retrying cannot fix these; the
    // user has to act.
    if (status == 400 || status == 403 || status == 404 || status == 410) {
      return _fail(draft, error);
    }
    // Everything else (timeouts after sending, 5xx, lost responses, auth
    // hiccups) leaves the outcome unknown; the state on disk decides
    // whether the next round runs the dedup check first.
    return SubmitRetryLater(await _retryLater(draft, error));
  }

  Future<SubmitFailed> _fail(QueuedDraft draft, DioException error) async {
    final errors = _validationErrors(error);
    final failed = draft.copyWith(
      state: QueuedDraftState.failed,
      lastError: errors.isEmpty
          ? 'HTTP ${error.response?.statusCode}'
          : errors.join('; '),
    );
    await _store.save(failed);
    return SubmitFailed(failed);
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
