import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../api/models/bundle.dart';
import '../../api/models/geojson.dart';
import '../../api/models/issue_summary.dart';
import 'issues_store.dart';

/// What a cache load brings back: the state to show immediately, plus when
/// it was last known good (restored into the sync status).
class CachedIssues {
  const CachedIssues({required this.state, this.syncedAt});

  final IssuesState state;
  final DateTime? syncedAt;
}

/// The issues held on disk for one connection, so a restart — online or
/// not — starts from the last known state instead of a blank screen. The
/// change feed was built for exactly this: the file is the in-memory state
/// plus its cursor, and catching up is one feed request from that cursor.
///
/// Issues persist as the server's own JSON (summary payload + GeoJSON
/// geometry), re-parsed on load; only the four-field project shape is
/// hand-written. Writes are atomic (sidecar + rename), like the outbox.
class IssuesCache {
  IssuesCache(this._file);

  final File _file;

  static const _version = 1;

  Future<CachedIssues?> load() async {
    try {
      if (!await _file.exists()) {
        return null;
      }
      final json =
          jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      if (json['version'] != _version) {
        return null;
      }
      final issues = <int, BundleIssue>{};
      for (final entry in json['issues'] as List<dynamic>? ?? const []) {
        final map = entry as Map<String, dynamic>;
        final summary = IssueSummary.fromJson(
          map['summary'] as Map<String, dynamic>,
        );
        final geometryJson = map['geometry'] as Map<String, dynamic>?;
        issues[summary.id] = BundleIssue(
          summary: summary,
          geometry: IssueGeometry.fromJson(geometryJson),
          geometryJson: geometryJson,
        );
      }
      final state = IssuesState(
        byId: issues,
        projects: [
          for (final project in json['projects'] as List<dynamic>? ?? const [])
            BundleProject.fromJson(project as Map<String, dynamic>),
        ],
        cursor: json['cursor'] as String? ?? '',
      );
      if (state.cursor.isEmpty) {
        return null;
      }
      return CachedIssues(
        state: state,
        syncedAt: DateTime.tryParse(json['synced_at'] as String? ?? ''),
      );
    } on Exception catch (error) {
      // A corrupt cache is not worth failing a launch over; the online
      // path rebuilds it from a fresh bundle.
      debugPrint('Issues cache unreadable, ignoring: $error');
      return null;
    }
  }

  Future<void> save(IssuesState state, {required DateTime syncedAt}) async {
    final json = <String, dynamic>{
      'version': _version,
      'cursor': state.cursor,
      'synced_at': syncedAt.toUtc().toIso8601String(),
      'projects': [for (final project in state.projects) project.toCacheJson()],
      'issues': [
        for (final issue in state.byId.values)
          {
            'summary': issue.summary.raw,
            if (issue.geometryJson != null) 'geometry': issue.geometryJson,
          },
      ],
    };
    final sidecar = File('${_file.path}.tmp');
    await sidecar.writeAsString(jsonEncode(json), flush: true);
    await sidecar.rename(_file.path);
  }

  Future<void> clear() async {
    if (await _file.exists()) {
      await _file.delete();
    }
  }
}
