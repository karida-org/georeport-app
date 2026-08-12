import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models/project_schema.dart';
import '../../connections/connection_manager.dart';
import '../issues/issue_providers.dart';
import 'schema_cache.dart';

/// The editing schema for one project, driving the create form. Successful
/// fetches refresh the on-disk cache; in a dead spot the last-known schema
/// keeps the capture form usable.
final projectSchemaProvider = FutureProvider.autoDispose
    .family<ProjectSchema, int>((ref, projectId) async {
      final client = ref.watch(activeClientProvider);
      final connectionId = ref
          .watch(connectionManagerProvider)
          .value
          ?.active
          ?.connection
          .id;
      final cache = await ref.watch(schemaCacheProvider.future);

      Future<ProjectSchema?> fromCache() async {
        final cached = connectionId == null
            ? null
            : await cache.read(connectionId, projectId);
        return cached == null ? null : ProjectSchema.fromJson(cached);
      }

      try {
        final json = await client.projectSchemaJson(projectId);
        final schema = ProjectSchema.fromJson(json);
        // A trackerless schema is what a captive portal's 200-with-HTML
        // answer parses to: never let it replace a known-good cache, and
        // prefer the cache over an unusable form.
        if (schema.trackers.isEmpty) {
          return await fromCache() ?? schema;
        }
        if (connectionId != null) {
          await cache.write(connectionId, projectId, json);
        }
        return schema;
        // The fallback must also cover parse failures on an unexpected
        // response shape, which throw TypeError, not DioException.
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        final cached = await fromCache();
        if (cached != null) {
          return cached;
        }
        rethrow;
      }
    });
