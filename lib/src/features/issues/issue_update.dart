import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/image_shrink.dart';
import '../../capture/issue_draft.dart';
import '../issues/issues_store.dart';
import 'issue_providers.dart';

/// The issue changed on the server since this client loaded it. The caller
/// reloads and lets the user re-apply their input; silent overwrites are
/// exactly what lock_version exists to prevent.
class StaleIssueException implements Exception {
  const StaleIssueException();
}

/// The `PUT /issues/:id.json` body for a field-side update: status change
/// and/or a note, always pinned to the lock_version the client loaded.
Map<String, dynamic> buildIssueUpdatePayload({
  required int lockVersion,
  int? statusId,
  String? notes,
  List<Map<String, String>> uploads = const [],
}) {
  return {
    'issue': {
      'lock_version': lockVersion,
      'status_id': ?statusId,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (uploads.isNotEmpty) 'uploads': uploads,
    },
  };
}

/// Whether a rejected update means "someone changed the issue first".
/// RedMica's REST answers a stale lock_version with 422 and an EMPTY errors
/// list (not 409), so both shapes classify as a conflict; a 422 with real
/// messages stays a validation failure.
bool isStaleWriteError(DioException error) {
  final status = error.response?.statusCode;
  if (status == 409) {
    return true;
  }
  if (status != 422) {
    return false;
  }
  final data = error.response?.data;
  final errors = data is Map<String, dynamic> ? data['errors'] : null;
  return errors == null || (errors is List && errors.isEmpty);
}

// Deliberately NOT autoDispose: submit() works across async gaps (uploads,
// the PUT), and an autoDispose provider read once from a sheet is disposed
// before those complete, killing its Ref mid-flight.
final issueUpdaterProvider = Provider<IssueUpdater>(IssueUpdater.new);

/// Applies a field-side update to an issue: uploads any photos through the
/// token flow (shrunk like every other upload), sends the update with the
/// loaded lock_version, and refreshes the document and list on success.
class IssueUpdater {
  IssueUpdater(this._ref);

  final Ref _ref;

  Future<void> submit({
    required int issueId,
    required int lockVersion,
    int? statusId,
    String? notes,
    List<DraftPhoto> photos = const [],
  }) async {
    final client = _ref.read(activeClientProvider);
    final uploads = <Map<String, String>>[];
    for (final photo in photos) {
      final shrunk = await shrinkForUpload(photo.bytes, photo.contentType);
      final token = await client.uploadFile(shrunk, photo.filename);
      uploads.add({
        'token': token,
        'filename': photo.filename,
        if (photo.contentType case final String type) 'content_type': type,
      });
    }
    try {
      await client.updateIssue(
        issueId,
        buildIssueUpdatePayload(
          lockVersion: lockVersion,
          statusId: statusId,
          notes: notes,
          uploads: uploads,
        ),
      );
    } on DioException catch (error) {
      if (isStaleWriteError(error)) {
        // Reload so the user reviews the fresh state before retrying.
        _ref.invalidate(issueDocumentProvider(issueId));
        throw const StaleIssueException();
      }
      rethrow;
    }
    _ref.invalidate(issueDocumentProvider(issueId));
    _ref.invalidate(issuesProvider);
  }
}
