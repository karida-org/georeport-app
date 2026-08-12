import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Last-known project schemas on disk, so the capture form still works in a
/// dead spot: fetched schemas are written through here, and a failed fetch
/// falls back to whatever was cached last. Each connection gets its own
/// directory (the id is percent-encoded, so it can neither collide with
/// another id nor escape the cache root), so two Redmine instances can
/// never serve each other's fields.
class SchemaCache {
  SchemaCache(this._root);

  final Directory _root;

  File _file(String connectionId, int projectId) => File(
    '${_root.path}/${Uri.encodeComponent(connectionId)}/$projectId.json',
  );

  Future<Map<String, dynamic>?> read(String connectionId, int projectId) async {
    final file = _file(connectionId, projectId);
    try {
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Exception {
      // A corrupt file would fail on every read; drop it so the next
      // successful fetch can write a valid one.
      try {
        await file.delete();
      } on Exception {
        // Nothing left to do; the next write truncates it anyway.
      }
      return null;
    }
  }

  /// Atomic (sidecar write + rename): a kill mid-write must not corrupt
  /// the one copy that offline capture depends on.
  Future<void> write(
    String connectionId,
    int projectId,
    Map<String, dynamic> schema,
  ) async {
    final target = _file(connectionId, projectId);
    target.parent.createSync(recursive: true);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(jsonEncode(schema), flush: true);
    await temp.rename(target.path);
  }
}

final schemaCacheProvider = FutureProvider<SchemaCache>((ref) async {
  final documents = await getApplicationDocumentsDirectory();
  return SchemaCache(Directory('${documents.path}/schema_cache'));
});
