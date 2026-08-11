/// Exercises the gtt_sync contract against a live instance, end to end:
/// capabilities probe, cross-project bundle, and one issue document.
///
/// Usage: `dart run tool/live_check.dart <base-url> [api-key]`
library;

import 'dart:io';

import 'package:georeport/src/api/gtt_sync_client.dart';
import 'package:georeport/src/api/models/geojson.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/live_check.dart <base-url> [api-key]');
    exitCode = 64;
    return;
  }
  final client = GttSyncClient(
    baseUrl: args[0],
    apiKey: args.length > 1 ? args[1] : null,
  );

  final capabilities = await client.capabilities();
  stdout.writeln(
    'capabilities: ${capabilities.plugin} ${capabilities.version} '
    'on Redmine ${capabilities.redmineVersion}',
  );
  stdout.writeln(
    '  bundle=${capabilities.supports('project_bundle')} '
    'change_feed=${capabilities.supports('change_feed')} '
    'schema=${capabilities.supports('schema_introspection')} '
    'oauth_client=${capabilities.oauth?.clientId != null}',
  );

  final bundle = await client.bundle();
  final byType = <String, int>{};
  for (final issue in bundle.placed) {
    final type = issue.geometry!.runtimeType.toString();
    byType[type] = (byType[type] ?? 0) + 1;
  }
  stdout.writeln(
    'bundle: ${bundle.projects.length} projects, '
    '${bundle.issues.length} issues '
    '($byType, unplaced=${bundle.unplaced.length})',
  );

  final firstPlaced = bundle.placed.first.summary;
  final issue = await client.issueDocument(firstPlaced.id);
  stdout.writeln(
    'issue #${issue.id}: "${issue.subject}" '
    '[${issue.tracker.name}/${issue.status.name}] '
    'geometry=${issue.geometry is PointGeometry ? 'point' : issue.geometry.runtimeType} '
    'journals=${issue.journals.length} '
    'transitions=${issue.editable.statusTransitions.map((s) => s.name).join(',')}',
  );
  stdout.writeln('live check passed');
}
