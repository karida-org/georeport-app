import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/bundle.dart';
import '../../api/models/issue_document.dart';
import '../connect/connection_provider.dart';

/// The cross-project bundle for the active connection.
final bundleProvider = FutureProvider.autoDispose<Bundle>((ref) async {
  final connection = ref.watch(connectionProvider);
  if (connection == null) {
    throw StateError('Not connected');
  }
  return connection.client.bundle();
});

/// A single issue document, fetched on demand.
final issueDocumentProvider = FutureProvider.autoDispose
    .family<IssueDocument, int>((ref, issueId) async {
      final connection = ref.watch(connectionProvider);
      if (connection == null) {
        throw StateError('Not connected');
      }
      return connection.client.issueDocument(issueId);
    });
