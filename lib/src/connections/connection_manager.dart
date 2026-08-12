import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/base_url.dart';
import '../api/client_auth.dart';
import '../api/gtt_sync_client.dart';
import '../api/models/capabilities.dart';
import '../api/models/current_user.dart';
import '../api/models/gtt_style_settings.dart';
import '../auth/oauth_config.dart';
import '../auth/oauth_flow.dart';
import '../auth/oauth_tokens.dart';
import '../auth/token_manager.dart';
import 'connection.dart';
import 'connection_store.dart';
import 'scope_drift.dart';

/// The live, authenticated session for one saved connection.
class ActiveConnection {
  const ActiveConnection({
    required this.connection,
    required this.client,
    required this.capabilities,
    this.styleSettings = const GttStyleSettings(),
    this.currentUser,
    this.newScopes = const [],
  });

  final Connection connection;
  final GttSyncClient client;
  final Capabilities capabilities;

  /// Instance styling (status colors, tracker names/icons); defaults when
  /// the instance does not serve it.
  final GttStyleSettings styleSettings;

  /// The signed-in account, when the token or role allows reading it; null
  /// hides identity-scoped features such as "assigned to me".
  final CurrentUser? currentUser;

  /// Scopes the server advertises beyond what this session's OAuth grant
  /// carries; non-empty invites a re-authorization (see [newlyAdvertisedScopes]).
  /// Always empty for API-key sessions.
  final List<String> newScopes;
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
    await _commit(connection, await _enrich(connection, client, capabilities));
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
    final tokens = _withRequestedScopes(
      await ref.read(oauthFlowProvider).authorize(config),
      config,
    );
    final connection = _newConnection(normalized, ConnectionAuthKind.oauth);
    await _persistOAuthSecret(connection.id, config, tokens);
    final client = _oauthClient(connection, config, tokens);
    await _commit(connection, await _enrich(connection, client, capabilities));
  }

  /// Activates a saved connection. Failures (dead session, offline) throw
  /// to the caller and leave the saved list untouched, so the UI can offer
  /// re-authentication instead of losing state.
  Future<void> activate(String connectionId) async {
    final current = state.value;
    final connection = current?.connections
        .where((Connection c) => c.id == connectionId)
        .firstOrNull;
    if (connection == null) {
      return;
    }
    final active = await _activate(connection);
    // The activation round trip can race a removal; commit against the
    // list as it is NOW, and only if the connection still exists.
    final latest = state.value ?? current!;
    if (!latest.connections.any((c) => c.id == connectionId)) {
      return;
    }
    await _store.saveActiveId(connection.id);
    state = AsyncData(
      ConnectionsState(connections: latest.connections, active: active),
    );
  }

  /// Renames a saved connection; the id, credentials, and everything else
  /// stay untouched. A connection removed in the meantime is left alone.
  Future<void> rename(String connectionId, String label) async {
    final current = state.value;
    final trimmed = label.trim();
    if (current == null || trimmed.isEmpty || _saved(connectionId) == null) {
      return;
    }
    final connections = [
      for (final connection in current.connections)
        if (connection.id == connectionId)
          Connection(
            id: connection.id,
            label: trimmed,
            baseUrl: connection.baseUrl,
            authKind: connection.authKind,
          )
        else
          connection,
    ];
    await _store.saveConnections(connections);
    var active = current.active;
    if (active != null && active.connection.id == connectionId) {
      active = ActiveConnection(
        connection: connections.firstWhere((c) => c.id == connectionId),
        client: active.client,
        capabilities: active.capabilities,
        styleSettings: active.styleSettings,
        currentUser: active.currentUser,
        newScopes: active.newScopes,
      );
    }
    state = AsyncData(
      ConnectionsState(connections: connections, active: active),
    );
  }

  /// Re-runs the browser sign-in for a saved OAuth connection whose session
  /// died (revoked token, expired refresh token), writing the new tokens
  /// under the existing connection id so its identity survives.
  Future<void> reauthenticateOAuth(String connectionId) async {
    final connection = _saved(connectionId);
    if (connection == null) {
      return;
    }
    final capabilities = await probe(connection.baseUrl);
    final config = oauthConfigFor(connection.baseUrl, capabilities);
    if (config == null) {
      throw const OAuthFlowException(
        'This instance does not offer app sign-in.',
      );
    }
    final tokens = _withRequestedScopes(
      await ref.read(oauthFlowProvider).authorize(config),
      config,
    );
    // The browser flow takes long enough for a concurrent removal; never
    // write credentials for a connection that no longer exists.
    if (_saved(connectionId) == null) {
      return;
    }
    await _persistOAuthSecret(connectionId, config, tokens);
    await activate(connectionId);
  }

  /// Replaces a saved connection's API key in place (rotated keys), after
  /// verifying the new key against the instance.
  Future<void> reauthenticateApiKey(String connectionId, String apiKey) async {
    final connection = _saved(connectionId);
    if (connection == null) {
      return;
    }
    final client = GttSyncClient(
      baseUrl: connection.baseUrl,
      auth: ApiKeyAuth(apiKey),
    );
    await client.validateAuth();
    if (_saved(connectionId) == null) {
      return;
    }
    await _store.writeSecret(connectionId, {
      'kind': 'api_key',
      'api_key': apiKey,
    });
    await activate(connectionId);
  }

  Connection? _saved(String connectionId) => state.value?.connections
      .where((Connection c) => c.id == connectionId)
      .firstOrNull;

  Future<void> remove(String connectionId) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    await _revokeBestEffort(connectionId);
    await _store.deleteSecret(connectionId);
    await ref.read(scopeDriftDismissalsProvider).clear(connectionId);
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
    List<String> grantedScopes = const [];
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
      grantedScopes = tokens.scopes;
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
    return _enrich(
      connection,
      client,
      capabilities,
      newScopes: newlyAdvertisedScopes(
        granted: grantedScopes,
        advertised: capabilities.oauth?.mobileClient?.scopes ?? const [],
      ),
    );
  }

  /// Completes a session with optional per-instance context: styling and the
  /// signed-in account. Both are decoration; failures degrade to defaults.
  Future<ActiveConnection> _enrich(
    Connection connection,
    GttSyncClient client,
    Capabilities capabilities, {
    List<String> newScopes = const [],
  }) async {
    GttStyleSettings style = const GttStyleSettings();
    CurrentUser? user;
    try {
      style = await client.styleSettings();
    } on Exception catch (error) {
      debugPrint('Style settings unavailable: $error');
    }
    try {
      final fetched = await client.currentUser();
      user = fetched.displayName.isEmpty ? null : fetched;
    } on Exception catch (error) {
      debugPrint('Current user unavailable: $error');
    }
    return ActiveConnection(
      connection: connection,
      client: client,
      capabilities: capabilities,
      styleSettings: style,
      currentUser: user,
      newScopes: newScopes,
    );
  }

  /// Doorkeeper reports the granted scopes on the token response; a server
  /// that omits the field granted exactly what was requested (RFC 6749).
  OAuthTokens _withRequestedScopes(OAuthTokens tokens, OAuthConfig config) {
    if (tokens.scopes.isNotEmpty) {
      return tokens;
    }
    return OAuthTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: tokens.expiresAt,
      scopes: config.scopes,
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
