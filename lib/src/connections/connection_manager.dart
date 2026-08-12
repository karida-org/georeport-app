import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/base_url.dart';
import '../api/client_auth.dart';
import '../api/gtt_sync_client.dart';
import '../api/models/capabilities.dart';
import '../auth/oauth_config.dart';
import '../auth/oauth_flow.dart';
import '../auth/oauth_tokens.dart';
import '../auth/token_manager.dart';
import 'connection.dart';
import 'connection_store.dart';

/// The live, authenticated session for one saved connection.
class ActiveConnection {
  const ActiveConnection({
    required this.connection,
    required this.client,
    required this.capabilities,
  });

  final Connection connection;
  final GttSyncClient client;
  final Capabilities capabilities;
}

/// What the UI observes: the saved list and the currently active session.
class ConnectionsState {
  const ConnectionsState({required this.connections, this.active});

  final List<Connection> connections;
  final ActiveConnection? active;
}

final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());

final oauthFlowProvider = Provider<OAuthFlow>((ref) => OAuthFlow());

final connectionManagerProvider =
    AsyncNotifierProvider<ConnectionManager, ConnectionsState>(
      ConnectionManager.new,
    );

/// Owns the connection list and the active session: onboarding (API key and
/// OAuth), switching, and removal. Secrets go through [ConnectionStore] into
/// the platform secure storage; refreshed OAuth tokens are persisted back.
class ConnectionManager extends AsyncNotifier<ConnectionsState> {
  late ConnectionStore _store;

  @override
  Future<ConnectionsState> build() async {
    _store = ConnectionStore(ref.watch(secretStoreProvider));
    final connections = await _store.loadConnections();
    final activeId = await _store.loadActiveId();
    final saved = connections
        .where((Connection c) => c.id == activeId)
        .firstOrNull;
    if (saved == null) {
      return ConnectionsState(connections: connections);
    }
    try {
      final active = await _activate(saved);
      return ConnectionsState(connections: connections, active: active);
    } on Exception catch (error) {
      // Offline or the instance is unreachable: keep the saved list so the
      // user can retry or pick another instance instead of losing state.
      debugPrint('Could not reconnect to ${saved.baseUrl}: $error');
      return ConnectionsState(connections: connections);
    }
  }

  /// Probes an instance URL without credentials, so onboarding can show what
  /// the server offers and whether OAuth sign-in is available.
  Future<Capabilities> probe(String baseUrl) {
    return GttSyncClient(baseUrl: baseUrl).capabilities();
  }

  Future<void> connectWithApiKey({
    required String baseUrl,
    required String apiKey,
  }) async {
    final normalized = normalizeBaseUrl(baseUrl);
    final client = GttSyncClient(baseUrl: normalized, auth: ApiKeyAuth(apiKey));
    final capabilities = await client.capabilities();
    // The probe is public, so it succeeds with any key; verify the key on an
    // authenticated call before anything is persisted.
    await client.validateAuth();
    final connection = _newConnection(normalized, ConnectionAuthKind.apiKey);
    await _store.writeSecret(connection.id, {
      'kind': 'api_key',
      'api_key': apiKey,
    });
    await _commit(
      connection,
      ActiveConnection(
        connection: connection,
        client: client,
        capabilities: capabilities,
      ),
    );
  }

  /// Runs the browser sign-in against an instance advertising a mobile OAuth
  /// application, then saves the connection with its tokens.
  Future<void> connectWithOAuth({
    required String baseUrl,
    required Capabilities capabilities,
  }) async {
    final normalized = normalizeBaseUrl(baseUrl);
    final config = oauthConfigFor(normalized, capabilities);
    if (config == null) {
      throw const OAuthFlowException(
        'This instance does not offer app sign-in.',
      );
    }
    final tokens = await ref.read(oauthFlowProvider).authorize(config);
    final connection = _newConnection(normalized, ConnectionAuthKind.oauth);
    await _persistOAuthSecret(connection.id, config, tokens);
    final client = _oauthClient(connection, config, tokens);
    await _commit(
      connection,
      ActiveConnection(
        connection: connection,
        client: client,
        capabilities: capabilities,
      ),
    );
  }

  Future<void> activate(String connectionId) async {
    final current = state.value;
    final connection = current?.connections
        .where((Connection c) => c.id == connectionId)
        .firstOrNull;
    if (connection == null) {
      return;
    }
    state = await AsyncValue.guard(() async {
      final active = await _activate(connection);
      await _store.saveActiveId(connection.id);
      return ConnectionsState(
        connections: current!.connections,
        active: active,
      );
    });
  }

  Future<void> remove(String connectionId) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    await _revokeBestEffort(connectionId);
    await _store.deleteSecret(connectionId);
    final remaining = current.connections
        .where((Connection c) => c.id != connectionId)
        .toList();
    await _store.saveConnections(remaining);
    final active = current.active?.connection.id == connectionId
        ? null
        : current.active;
    if (active == null) {
      await _store.saveActiveId(null);
    }
    state = AsyncData(ConnectionsState(connections: remaining, active: active));
  }

  Future<void> disconnect() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    await _store.saveActiveId(null);
    state = AsyncData(ConnectionsState(connections: current.connections));
  }

  Future<ActiveConnection> _activate(Connection connection) async {
    final secret = await _store.readSecret(connection.id);
    if (secret == null) {
      throw StateError('No stored credentials for ${connection.label}');
    }
    final GttSyncClient client;
    if (secret['kind'] == 'oauth') {
      final config = OAuthConfig(
        authorizeUrl: '',
        tokenUrl: secret['token_url'] as String? ?? '',
        clientId: secret['client_id'] as String? ?? '',
        redirectUri: '',
        scopes: const [],
      );
      final tokens = OAuthTokens.fromJson(
        secret['tokens'] as Map<String, dynamic>? ?? const {},
      );
      client = _oauthClient(connection, config, tokens);
    } else {
      final apiKey = secret['api_key'];
      if (apiKey is! String || apiKey.isEmpty) {
        throw StateError('No stored credentials for ${connection.label}');
      }
      client = GttSyncClient(
        baseUrl: connection.baseUrl,
        auth: ApiKeyAuth(apiKey),
      );
    }
    final capabilities = await client.capabilities();
    return ActiveConnection(
      connection: connection,
      client: client,
      capabilities: capabilities,
    );
  }

  GttSyncClient _oauthClient(
    Connection connection,
    OAuthConfig config,
    OAuthTokens tokens,
  ) {
    final manager = TokenManager(
      tokenUrl: config.tokenUrl,
      clientId: config.clientId,
      tokens: tokens,
      onTokensChanged: (fresh) =>
          _persistOAuthSecret(connection.id, config, fresh),
    );
    return GttSyncClient(baseUrl: connection.baseUrl, auth: OAuthAuth(manager));
  }

  Future<void> _persistOAuthSecret(
    String connectionId,
    OAuthConfig config,
    OAuthTokens tokens,
  ) {
    return _store.writeSecret(connectionId, {
      'kind': 'oauth',
      'token_url': config.tokenUrl,
      'client_id': config.clientId,
      'tokens': tokens.toJson(),
    });
  }

  Future<void> _commit(Connection connection, ActiveConnection active) async {
    final current = state.value;
    final others = (current?.connections ?? const <Connection>[])
        .where((Connection c) => c.id != connection.id)
        .toList();
    final connections = [...others, connection];
    await _store.saveConnections(connections);
    await _store.saveActiveId(connection.id);
    state = AsyncData(
      ConnectionsState(connections: connections, active: active),
    );
  }

  Connection _newConnection(String baseUrl, ConnectionAuthKind kind) {
    final host = Uri.tryParse(baseUrl)?.host;
    return Connection(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: (host == null || host.isEmpty) ? baseUrl : host,
      baseUrl: baseUrl,
      authKind: kind,
    );
  }

  /// Deleting a connection should leave no live grant behind; failures are
  /// ignored because the secret is deleted locally either way.
  Future<void> _revokeBestEffort(String connectionId) async {
    try {
      final secret = await _store.readSecret(connectionId);
      if (secret == null || secret['kind'] != 'oauth') {
        return;
      }
      final tokens = OAuthTokens.fromJson(
        secret['tokens'] as Map<String, dynamic>? ?? const {},
      );
      final tokenUrl = secret['token_url'] as String? ?? '';
      if (tokens.accessToken.isEmpty || tokenUrl.isEmpty) {
        return;
      }
      final revokeUrl = tokenUrl.replaceFirst(RegExp(r'/token$'), '/revoke');
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      await dio.post<void>(
        revokeUrl,
        data: {
          'token': tokens.accessToken,
          'client_id': secret['client_id'] as String? ?? '',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on Exception catch (error) {
      debugPrint('Token revocation failed (ignored): $error');
    }
  }
}
