import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'connection.dart';

/// Minimal key-value contract over the platform secure storage, so tests can
/// substitute an in-memory map.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Persistence for the connection list, the active selection, and the
/// per-connection secret payloads. Everything lives in secure storage: the
/// list itself is not secret, but one store keeps deletion atomic enough and
/// leaves nothing behind on uninstall on iOS.
class ConnectionStore {
  ConnectionStore(this._store);

  static const _listKey = 'georeport.connections';
  static const _activeKey = 'georeport.active_connection';

  final SecretStore _store;

  Future<List<Connection>> loadConnections() async {
    final raw = await _store.read(_listKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final Object? decoded;
    try {
      decoded = json.decode(raw);
    } on FormatException {
      // Corrupt storage must never block startup; the user can re-add.
      return const [];
    }
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(Connection.fromJson)
        .where((connection) => connection.id.isNotEmpty)
        .toList();
  }

  Future<void> saveConnections(List<Connection> connections) => _store.write(
    _listKey,
    json.encode([for (final connection in connections) connection.toJson()]),
  );

  Future<String?> loadActiveId() => _store.read(_activeKey);

  Future<void> saveActiveId(String? id) async {
    if (id == null) {
      await _store.delete(_activeKey);
    } else {
      await _store.write(_activeKey, id);
    }
  }

  Future<Map<String, dynamic>?> readSecret(String connectionId) async {
    final raw = await _store.read(_secretKey(connectionId));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = json.decode(raw);
    } on FormatException {
      return null;
    }
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<void> writeSecret(String connectionId, Map<String, dynamic> secret) =>
      _store.write(_secretKey(connectionId), json.encode(secret));

  Future<void> deleteSecret(String connectionId) =>
      _store.delete(_secretKey(connectionId));

  String _secretKey(String connectionId) => 'georeport.secret.$connectionId';
}
