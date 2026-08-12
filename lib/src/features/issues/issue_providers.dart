import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/gtt_sync_client.dart';
import '../../api/models/bundle.dart';
import '../../api/models/issue_document.dart';
import '../../connections/connection_manager.dart';

/// The active connection's client; throws when nothing is connected, which
/// only happens if a data screen is reached without a session.
final activeClientProvider = Provider.autoDispose<GttSyncClient>((ref) {
  final client = ref.watch(connectionManagerProvider).value?.active?.client;
  if (client == null) {
    throw StateError('Not connected');
  }
  return client;
});

/// The cross-project bundle for the active connection.
final bundleProvider = FutureProvider.autoDispose<Bundle>((ref) {
  return ref.watch(activeClientProvider).bundle();
});

/// A single issue document, fetched on demand.
final issueDocumentProvider = FutureProvider.autoDispose
    .family<IssueDocument, int>((ref, issueId) {
      return ref.watch(activeClientProvider).issueDocument(issueId);
    });
