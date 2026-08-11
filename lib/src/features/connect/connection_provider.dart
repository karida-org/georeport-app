import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/gtt_sync_client.dart';
import '../../api/models/capabilities.dart';

/// The active connection: a client plus what its capabilities probe returned.
///
/// Spike scope: one in-memory connection at a time. Persistence and multiple
/// saved instances belong to the M1 connection manager.
class Connection {
  const Connection({required this.client, required this.capabilities});

  final GttSyncClient client;
  final Capabilities capabilities;
}

class ConnectionNotifier extends Notifier<Connection?> {
  @override
  Connection? build() => null;

  Future<Connection> connect({
    required String baseUrl,
    required String apiKey,
  }) async {
    final client = GttSyncClient(baseUrl: baseUrl, apiKey: apiKey);
    final capabilities = await client.capabilities();
    final connection = Connection(client: client, capabilities: capabilities);
    state = connection;
    return connection;
  }

  void disconnect() {
    state = null;
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, Connection?>(
  ConnectionNotifier.new,
);
