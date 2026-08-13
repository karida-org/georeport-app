import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/issue_document.dart';
import '../../connections/active_client.dart';

/// A single issue document, fetched on demand.
final issueDocumentProvider = FutureProvider.autoDispose
    .family<IssueDocument, int>((ref, issueId) {
      return ref.watch(activeClientProvider).issueDocument(issueId);
    });
