import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gtt_sync_client.dart';
import 'connection_manager.dart';

/// The active connection's client; throws when nothing is connected, which
/// only happens if a data screen is reached without a session.
///
/// Lives with the connection rather than with any one feature: every feature
/// that talks to the server needs it, and so do shared widgets such as the
/// authenticated image loader.
final activeClientProvider = Provider.autoDispose<GttSyncClient>((ref) {
  final client = ref.watch(connectionManagerProvider).value?.active?.client;
  if (client == null) {
    throw StateError('Not connected');
  }
  return client;
});
