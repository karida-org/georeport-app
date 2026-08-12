import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/models/bundle.dart';
import 'package:georeport/src/api/models/capabilities.dart';
import 'package:georeport/src/api/models/geojson.dart';
import 'package:georeport/src/api/models/issue_document.dart';

Map<String, dynamic> _fixture(String name) {
  final content = File('test/fixtures/$name').readAsStringSync();
  return json.decode(content) as Map<String, dynamic>;
}

void main() {
  group('Capabilities', () {
    test('parses the live probe shape', () {
      final capabilities = Capabilities.fromJson(_fixture('capabilities.json'));

      expect(capabilities.plugin, 'redmine_gtt_sync');
      expect(capabilities.redmineVersion, startsWith('7.'));
      expect(capabilities.supports('project_bundle'), isTrue);
      expect(capabilities.supports('change_feed'), isTrue);
      expect(capabilities.supports('wfs_t'), isFalse);
      expect(capabilities.supports('not_a_feature'), isFalse);

      final oauth = capabilities.oauth;
      expect(oauth, isNotNull);
      expect(oauth!.authorizeUrl, endsWith('/oauth/authorize'));
      expect(oauth.scopes, contains('use_gtt_sync'));
      expect(oauth.clientId, isNotNull);

      final mobile = oauth.mobileClient;
      expect(mobile, isNotNull, reason: 'fixture advertises a mobile client');
      expect(mobile!.clientId, isNotEmpty);
      expect(mobile.redirectUris, contains('georeport://oauth/callback'));
      expect(mobile.scopes, contains('use_gtt_sync'));
    });

    test('tolerates a probe without a clients map', () {
      final capabilities = Capabilities.fromJson({
        'plugin': 'redmine_gtt_sync',
        'version': '0.5.0',
        'redmine': {'version': '7.0.0'},
        'capabilities': const <String, dynamic>{},
        'oauth': {
          'authorize_url': 'https://x/oauth/authorize',
          'token_url': 'https://x/oauth/token',
          'scopes': const <String>[],
        },
      });
      expect(capabilities.oauth!.mobileClient, isNull);
    });
  });

  group('Bundle', () {
    test('parses the cross-project bundle shape', () {
      final bundle = Bundle.fromJson(_fixture('bundle.json'));

      expect(bundle.projects, hasLength(3));
      expect(bundle.placed, hasLength(4));
      expect(bundle.unplaced, hasLength(1));

      final point = bundle.placed.firstWhere(
        (issue) => issue.geometry is PointGeometry,
      );
      expect(point.summary.subject, isNotEmpty);
      expect(point.summary.lockVersion, greaterThanOrEqualTo(0));

      final line = bundle.placed.firstWhere(
        (issue) => issue.geometry is LineGeometry,
      );
      expect(line.geometry!.allPoints.length, greaterThan(1));

      final polygon = bundle.placed.firstWhere(
        (issue) => issue.geometry is PolygonGeometry,
      );
      expect(polygon.geometry!.allPoints.length, greaterThan(2));

      final unplaced = bundle.unplaced.first;
      expect(unplaced.geometry, isNull);
      expect(unplaced.summary.id, greaterThan(0));
    });

    test('parses a single-project bundle shape', () {
      final bundle = Bundle.fromJson({
        'project': {
          '@id': 'https://example.org/projects/demo',
          'id': 4,
          'identifier': 'demo',
          'name': 'Demo',
          'boundary': null,
        },
        'issues': {
          'point': {'type': 'FeatureCollection', 'features': <Object>[]},
          'line': {'type': 'FeatureCollection', 'features': <Object>[]},
          'polygon': {'type': 'FeatureCollection', 'features': <Object>[]},
          'unplaced': <Object>[],
        },
      });

      expect(bundle.projects, hasLength(1));
      expect(bundle.projects.single.identifier, 'demo');
      expect(bundle.projects.single.hasBoundary, isFalse);
      expect(bundle.issues, isEmpty);
    });
  });

  group('IssueDocument', () {
    test('parses the live JSON-LD document shape', () {
      final issue = IssueDocument.fromJson(_fixture('issue_document.json'));

      expect(issue.id, greaterThan(0));
      expect(issue.iri, contains('/issues/'));
      expect(issue.subject, isNotEmpty);
      expect(issue.status.name, isNotEmpty);
      expect(issue.tracker.name, isNotEmpty);
      expect(issue.project.name, isNotEmpty);
      expect(issue.geometry, isA<PointGeometry>());
      expect(issue.journals, isNotEmpty);
      expect(issue.editable.fields, contains('subject'));
      expect(issue.editable.statusTransitions, isNotEmpty);

      expect(issue.geometryJson, isNotNull);
      expect(issue.customFields, isNotEmpty);
      final severity = issue.customFields.firstWhere(
        (field) => field.name == 'Severity',
      );
      expect(severity.values, ['High']);

      final withDetails = issue.journals.lastWhere(
        (journal) => journal.details.isNotEmpty,
      );
      final change = withDetails.details.first;
      expect(change.name, 'subject');
      expect(change.oldValue, isNotNull);
      expect(change.newValue, contains('CONFIRMED'));

      final photo = issue.attachments.firstWhere(
        (attachment) => attachment.isImage,
      );
      expect(photo.thumbnailUrl, isNotNull);
    });

    test('treats absent keys as unset, not as errors', () {
      final issue = IssueDocument.fromJson({
        '@id': 'https://example.org/issues/1',
        'identifier': 1,
        'subject': 'Bare issue',
        'status': {'id': 1, 'name': 'New'},
        'tracker': {'id': 1, 'name': 'Bug'},
        'project': {'id': 1, 'identifier': 'p', 'name': 'P'},
        'is_private': false,
        'done_ratio': 0,
        'lock_version': 0,
        'journals': <Object>[],
        'relations': <Object>[],
        'attachments': <Object>[],
        'custom_fields': <Object>[],
        'editable': {'fields': <Object>[]},
      });

      expect(issue.description, isNull);
      expect(issue.assignedTo, isNull);
      expect(issue.geometry, isNull);
      expect(issue.dueDate, isNull);
      expect(issue.editable.canAddNotes, isFalse);
      expect(issue.editable.statusTransitions, isEmpty);
    });
  });
}
