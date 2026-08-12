import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connections/connection_manager.dart';
import '../router.dart';
import 'share_channel.dart';

final shareChannelProvider = Provider<ShareChannel>((ref) => ShareChannel());

/// Whether a session is active, as the narrow fact the intake needs.
final hasActiveConnectionProvider = Provider<bool>(
  (ref) => ref.watch(connectionManagerProvider).value?.active != null,
);

/// How delivered shares reach the capture flow; a seam for tests.
final shareNavigatorProvider = Provider<void Function(List<String> paths)>(
  (ref) =>
      (paths) => router.push('/capture', extra: paths),
);

final shareIntakeProvider = NotifierProvider<ShareIntake, List<String>>(
  ShareIntake.new,
);

/// Receives images shared from other apps and opens the capture flow with
/// them. Shares that arrive without an active session (a share cold-started
/// the app onto the connect screen) wait here and are delivered the moment
/// a connection becomes active.
class ShareIntake extends Notifier<List<String>> {
  StreamSubscription<List<String>>? _subscription;
  bool _started = false;

  @override
  List<String> build() {
    final channel = ref.watch(shareChannelProvider);
    _subscription?.cancel();
    _subscription = channel.shares.listen(_receive);
    ref.onDispose(() => _subscription?.cancel());
    if (!_started) {
      _started = true;
      unawaited(channel.start());
    }
    ref.listen(hasActiveConnectionProvider, (previous, next) {
      if (next) {
        _deliverIfReady();
      }
    });
    return const [];
  }

  void _receive(List<String> paths) {
    state = [...state, ...paths];
    _deliverIfReady();
  }

  void _deliverIfReady() {
    if (state.isEmpty || !ref.read(hasActiveConnectionProvider)) {
      return;
    }
    final paths = state;
    state = const [];
    ref.read(shareNavigatorProvider)(paths);
  }
}
