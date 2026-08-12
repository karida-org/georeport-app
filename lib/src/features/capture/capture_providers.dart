import 'package:dio/dio.dart';
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
      try {
        final json = await client.projectSchemaJson(projectId);
        if (connectionId != null) {
          await cache.write(connectionId, projectId, json);
        }
        return ProjectSchema.fromJson(json);
      } on DioException {
        final cached = connectionId == null
            ? null
            : await cache.read(connectionId, projectId);
        if (cached != null) {
          return ProjectSchema.fromJson(cached);
        }
        rethrow;
      }
    });
