import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the last talk with the instance worked, and when data was last
/// brought up to date. Fed by the issues store (initial load, pull-to-
/// refresh, and the periodic change-feed poll); shown in the shell's menu.
class SyncStatus {
  const SyncStatus({this.lastSyncAt, this.healthy = true});

  /// When the issues were last successfully synced; null before the first
  /// load completes.
  final DateTime? lastSyncAt;

  /// False after a failed sync attempt, until one succeeds again.
  final bool healthy;
}

/// Deliberately not autoDispose: the record outlives the issues store's
/// rebuilds, so "last sync" stays truthful while no screen holds the data.
final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(
  SyncStatusNotifier.new,
);

class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => const SyncStatus();

  void recordSuccess(DateTime at) =>
      state = SyncStatus(lastSyncAt: at, healthy: true);

  void recordFailure() =>
      state = SyncStatus(lastSyncAt: state.lastSyncAt, healthy: false);
}
