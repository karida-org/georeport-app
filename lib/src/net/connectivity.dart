import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the device has any network interface up. This is about the
/// device, not the server: being offline is a normal part of field work
/// and shown calmly, while a server that fails on a working network is
/// the alarming case (SyncStatus.healthy).
final connectivityStreamProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  yield anyNetwork(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(anyNetwork);
});

/// Unknown (during startup) counts as online, so nothing flashes "Offline"
/// before the first reading arrives.
final isOnlineProvider = Provider<bool>(
  (ref) => ref.watch(connectivityStreamProvider).value ?? true,
);

/// True when any interface is up; connectivity_plus reports the active
/// interfaces as a list, with [ConnectivityResult.none] as its own entry.
bool anyNetwork(List<ConnectivityResult> results) =>
    results.any((result) => result != ConnectivityResult.none);
