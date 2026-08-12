import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api/models/capabilities.dart';
import '../api/models/current_user.dart';
import '../api/models/gtt_style_settings.dart';

/// What an offline resume needs to enter a session without the server:
/// the last known capabilities, styling, and identity.
class ConnectionMeta {
  const ConnectionMeta({
    required this.capabilities,
    required this.styleSettings,
    this.currentUser,
  });

  final Capabilities capabilities;
  final GttStyleSettings styleSettings;
  final CurrentUser? currentUser;
}

/// Per-connection session metadata on disk (server payloads verbatim,
/// re-parsed on load), written after every successful activation and read
/// when the instance cannot be reached. None of it is secret — credentials
/// stay in the platform secure storage.
class ConnectionMetaCache {
  ConnectionMetaCache(this._directory);

  final Directory _directory;

  static const _version = 1;

  File _file(String connectionId) =>
      File('${_directory.path}/connection-meta-$connectionId.json');

  Future<void> save(
    String connectionId, {
    required Capabilities capabilities,
    required GttStyleSettings styleSettings,
    CurrentUser? currentUser,
  }) async {
    final file = _file(connectionId);
    final sidecar = File('${file.path}.tmp');
    await sidecar.writeAsString(
      jsonEncode({
        'version': _version,
        'capabilities': capabilities.raw,
        'style': styleSettings.raw,
        // A fallback identity (empty raw payload) is not worth caching.
        if (currentUser != null && currentUser.raw.isNotEmpty)
          'user': currentUser.raw,
      }),
      flush: true,
    );
    await sidecar.rename(file.path);
  }

  Future<ConnectionMeta?> load(String connectionId) async {
    try {
      final file = _file(connectionId);
      if (!await file.exists()) {
        return null;
      }
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['version'] != _version) {
        return null;
      }
      final capabilities = json['capabilities'];
      if (capabilities is! Map<String, dynamic>) {
        return null;
      }
      final style = json['style'];
      final user = json['user'];
      final parsedUser = user is Map<String, dynamic>
          ? CurrentUser.fromJson(user)
          : null;
      return ConnectionMeta(
        capabilities: Capabilities.fromJson(capabilities),
        styleSettings: style is Map<String, dynamic>
            ? GttStyleSettings.fromJson(style)
            : const GttStyleSettings(),
        // The parser's fallback (no usable identity) reads as no user, the
        // same rule the live activation applies.
        currentUser: (parsedUser?.displayName.isEmpty ?? true)
            ? null
            : parsedUser,
      );
      // Catch-all on purpose: malformed shapes throw TypeError (an Error,
      // not an Exception) from the casts, and a corrupt cache must read as
      // absent instead of failing the resume.
      // ignore: avoid_catches_without_on_clauses
    } catch (error) {
      debugPrint('Connection meta cache unreadable, ignoring: $error');
      return null;
    }
  }

  /// Removes the snapshot and any leftover sidecar from an interrupted
  /// write: forgetting must leave no session metadata behind.
  Future<void> clear(String connectionId) async {
    try {
      final file = _file(connectionId);
      for (final target in [file, File('${file.path}.tmp')]) {
        if (await target.exists()) {
          await target.delete();
        }
      }
    } on Exception catch (error) {
      debugPrint('Connection meta cache cleanup failed (ignored): $error');
    }
  }
}

/// True for failures that mean "the server could not be reached" — the ones
/// an offline resume may bridge. Anything the server actually said (4xx,
/// 5xx) is not bridged: a real answer must win over cached state.
bool isUnreachableError(Object error) {
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError => true,
      DioExceptionType.unknown => error.error is SocketException,
      _ => false,
    };
  }
  return error is SocketException;
}
