import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/project_schema.dart';
import '../../capture/issue_draft.dart';
import '../issues/issue_providers.dart';

/// The editing schema for one project, driving the create form.
final projectSchemaProvider = FutureProvider.autoDispose
    .family<ProjectSchema, int>((ref, projectId) {
      return ref.watch(activeClientProvider).projectSchema(projectId);
    });

/// Uploads the draft's photos (token flow) and creates the issue.
/// Returns the new issue id. Failures throw; the caller keeps the draft so
/// nothing the user entered is lost.
final submitDraftProvider = Provider.autoDispose(
  (ref) => (IssueDraft draft) async {
    final client = ref.read(activeClientProvider);
    final uploads = <Map<String, String>>[];
    for (final photo in draft.photos) {
      final token = await client.uploadFile(photo.bytes, photo.filename);
      uploads.add({
        'token': token,
        'filename': photo.filename,
        if (photo.contentType case final String type) 'content_type': type,
      });
    }
    return client.createIssue(draft.toPayload(uploads));
  },
);
