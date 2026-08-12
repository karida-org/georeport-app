import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Last-known project schemas on disk, so the capture form still works in a
/// dead spot: fetched schemas are written through here, and a failed fetch
/// falls back to whatever was cached last. Keyed per connection so two
/// Redmine instances can never serve each other's fields.
class SchemaCache {
  SchemaCache(this._root);

  final Directory _root;

  File _file(String connectionId, int projectId) =>
      File('${_root.path}/$connectionId-$projectId.json');

  Future<Map<String, dynamic>?> read(String connectionId, int projectId) async {
    try {
      final file = _file(connectionId, projectId);
      if (!file.existsSync()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Exception {
      return null;
    }
  }

  Future<void> write(
    String connectionId,
    int projectId,
    Map<String, dynamic> schema,
  ) async {
    _root.createSync(recursive: true);
    await _file(connectionId, projectId).writeAsString(jsonEncode(schema));
  }
}

final schemaCacheProvider = FutureProvider<SchemaCache>((ref) async {
  final documents = await getApplicationDocumentsDirectory();
  return SchemaCache(Directory('${documents.path}/schema_cache'));
});
