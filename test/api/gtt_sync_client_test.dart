import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/gtt_sync_client.dart';

import '../helpers/scripted_adapter.dart';

/// A client whose HTTP layer is scripted, so the tests are about what the
/// client asks for and what it makes of the answer.
({GttSyncClient client, ScriptedAdapter adapter}) _client({
  List<ScriptedReply> replies = const [ScriptedReply(200)],
  String baseUrl = 'https://redmine.example.org',
}) {
  final adapter = ScriptedAdapter(replies);
  final dio = Dio(BaseOptions(baseUrl: baseUrl))..httpClientAdapter = adapter;
  return (client: GttSyncClient(baseUrl: baseUrl, dio: dio), adapter: adapter);
}

void main() {
  group('validateAuth', () {
    test('accepts a response that names a real user', () async {
      final t = _client(
        replies: [
          const ScriptedReply(200, {
            'user': {'id': 5, 'login': 'surveyor'},
          }),
        ],
      );

      await expectLater(t.client.validateAuth(), completes);
      expect(t.adapter.requests.single.uri.path, '/users/current.json');
    });

    test('rejects a 200 that carries no user', () async {
      // The bug this guards: a contract endpoint can answer an anonymous
      // caller with an empty payload, so "some endpoint replied 200" was not
      // evidence the credentials were accepted. Asking who am I is.
      final t = _client(replies: [const ScriptedReply(200)]);

      await expectLater(t.client.validateAuth(), throwsA(isA<StateError>()));
    });

    test('rejects a user without a usable id', () async {
      for (final id in [0, -1, 'five', null]) {
        final t = _client(
          replies: [
            ScriptedReply(200, {
              'user': {'id': id},
            }),
          ],
        );

        await expectLater(
          t.client.validateAuth(),
          throwsA(isA<StateError>()),
          reason: 'id $id should not count as accepted',
        );
      }
    });
  });

  group('createIssue', () {
    test('returns the new id', () async {
      final t = _client(
        replies: [
          const ScriptedReply(201, {
            'issue': {'id': 4242},
          }),
        ],
      );

      expect(await t.client.createIssue({'issue': <String, dynamic>{}}), 4242);
    });

    test('fails loudly when the response carries no id', () async {
      // Returning something wrong here would tell the outbox a draft landed
      // when it did not, and the draft would be dropped.
      final t = _client(replies: [const ScriptedReply(201)]);

      await expectLater(
        t.client.createIssue(const {}),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('uploadFile', () {
    test('sends the bytes with the filename and returns the token', () async {
      final t = _client(
        replies: [
          const ScriptedReply(201, {
            'upload': {'token': '7.abcdef'},
          }),
        ],
      );

      final token = await t.client.uploadFile([1, 2, 3], 'photo.jpg');

      expect(token, '7.abcdef');
      final request = t.adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/uploads.json');
      expect(request.uri.queryParameters['filename'], 'photo.jpg');
      // Dio stringifies header values on the way out.
      expect('${request.headers['Content-Length']}', '3');
      expect(
        request.body,
        isA<Uint8List>(),
        reason:
            'bytes, not a stream: the 401 retry replays the same request, and '
            'a single-subscription stream is already consumed by then',
      );
    });

    test('fails loudly on a response with no token', () async {
      final t = _client(
        replies: [
          const ScriptedReply(201, {'upload': <String, dynamic>{}}),
        ],
      );

      await expectLater(
        t.client.uploadFile([1], 'photo.jpg'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('myIssuesCreatedSince', () {
    test('strips fractional seconds, which Redmine rejects', () async {
      // Redmine's created_on filter parser refuses a fractional part, and the
      // whole query fails rather than returning fewer rows.
      final t = _client(
        replies: [
          const ScriptedReply(200, {'issues': <Object>[]}),
        ],
      );

      await t.client.myIssuesCreatedSince(
        projectId: 4,
        since: DateTime.utc(2026, 8, 13, 9, 30, 15, 123),
      );

      final query = t.adapter.requests.single.uri.queryParameters;
      expect(query['created_on'], '>=2026-08-13T09:30:15Z');
      expect(query['author_id'], 'me');
      expect(
        query['status_id'],
        '*',
        reason: 'a closed issue is still one the user created',
      );
    });

    test('converts a local timestamp to UTC before formatting', () async {
      final t = _client(
        replies: [
          const ScriptedReply(200, {'issues': <Object>[]}),
        ],
      );
      final since = DateTime.utc(2026, 8, 13, 0, 30).toLocal();

      await t.client.myIssuesCreatedSince(projectId: 4, since: since);

      expect(
        t.adapter.requests.single.uri.queryParameters['created_on'],
        '>=2026-08-13T00:30:00Z',
      );
    });

    test('skips entries with no id rather than failing the batch', () async {
      final t = _client(
        replies: [
          const ScriptedReply(200, {
            'issues': [
              {'id': 1, 'subject': 'Pothole'},
              {'subject': 'no id'},
              {'id': 3},
            ],
          }),
        ],
      );

      final issues = await t.client.myIssuesCreatedSince(
        projectId: 4,
        since: DateTime.utc(2026),
      );

      expect(issues.map((i) => i.id), [1, 3]);
      expect(issues.last.subject, '', reason: 'a missing subject is not null');
    });

    test('returns nothing when the payload has no issues list', () async {
      final t = _client(replies: [const ScriptedReply(200)]);

      expect(
        await t.client.myIssuesCreatedSince(
          projectId: 4,
          since: DateTime.utc(2026),
        ),
        isEmpty,
      );
    });
  });

  group('changes', () {
    test('asks for known ids only when they were requested', () async {
      final withIds = _client(
        replies: [
          const ScriptedReply(200, {'issues': <Object>[]}),
        ],
      );
      await withIds.client.changes(since: 'tok', knownIds: true);
      expect(
        withIds.adapter.requests.single.uri.queryParameters['known_ids'],
        '1',
      );

      final without = _client(
        replies: [
          const ScriptedReply(200, {'issues': <Object>[]}),
        ],
      );
      await without.client.changes(since: 'tok');
      expect(
        without.adapter.requests.single.uri.queryParameters,
        isNot(contains('known_ids')),
        reason: 'the full id set is expensive; do not ask for it by accident',
      );
    });
  });

  group('timeEntries', () {
    test('sends dates only, and omits a bound that was not given', () async {
      final t = _client(
        replies: [
          const ScriptedReply(200, {'time_entries': <Object>[]}),
        ],
      );

      await t.client.timeEntries(from: DateTime.utc(2026, 8, 1, 13, 45));

      final query = t.adapter.requests.single.uri.queryParameters;
      expect(query['from'], '2026-08-01');
      expect(query, isNot(contains('to')));
    });
  });

  group('publishLocation', () {
    test('writes GeoJSON coordinates longitude first', () async {
      // Same trap as every other GeoJSON payload: swapped values are not just
      // in the wrong order, a latitude over 90 is not a valid coordinate.
      final t = _client(replies: [const ScriptedReply(204)]);

      await t.client.publishLocation(35.681236, 139.767125);

      final request = t.adapter.requests.single;
      expect(request.uri.path, '/gtt_sync/users/me/location');
      final location =
          (request.body! as Map<String, dynamic>)['location']
              as Map<String, dynamic>;
      expect(location['type'], 'Point');
      expect(location['coordinates'], [139.767125, 35.681236]);
    });
  });

  group('fetchBytes', () {
    test('passes a relative path through unchanged', () async {
      // Real image bytes, not text: 0xFF alone is not valid UTF-8, so this
      // payload proves the bytes arrive intact rather than round-tripping
      // through a string.
      const jpegHeader = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
      final t = _client(replies: [const ScriptedReply.bytes(200, jpegHeader)]);

      final bytes = await t.client.fetchBytes('/attachments/download/9/a.jpg');

      expect(bytes, jpegHeader);
      expect(
        t.adapter.requests.single.uri.toString(),
        'https://redmine.example.org/attachments/download/9/a.jpg',
      );
    });

    test('reduces an absolute URL to its path', () async {
      // The server advertises canonical URLs that may use a different host
      // from the one the user connected to. Following them would send this
      // client's credentials somewhere else, or reach an instance that does
      // not know them.
      final t = _client(
        replies: [
          const ScriptedReply.bytes(200, [0xFF, 0x01]),
        ],
      );

      await t.client.fetchBytes(
        'https://canonical.example.com/attachments/download/9/a.jpg',
      );

      expect(
        t.adapter.requests.single.uri.toString(),
        'https://redmine.example.org/attachments/download/9/a.jpg',
      );
    });

    test('does not repeat the base path of a sub-path instance', () async {
      // The regression this covers: on a Redmine hosted at /redmine, keeping
      // the whole path asked for /redmine/redmine/... and every attachment
      // 404ed.
      final t = _client(
        baseUrl: 'https://example.org/redmine',
        replies: [
          const ScriptedReply.bytes(200, [0xFF, 0x01]),
        ],
      );

      await t.client.fetchBytes(
        'https://example.org/redmine/attachments/download/9/a.jpg',
      );

      expect(
        t.adapter.requests.single.uri.toString(),
        'https://example.org/redmine/attachments/download/9/a.jpg',
      );
    });

    test('carries the query string of an absolute URL', () async {
      // Thumbnails are a size query on the same path; dropping it returns the
      // full-size image.
      final t = _client(
        replies: [
          const ScriptedReply.bytes(200, [0xFF, 0x01]),
        ],
      );

      await t.client.fetchBytes(
        'https://redmine.example.org/attachments/thumbnail/9?size=200',
      );

      expect(t.adapter.requests.single.uri.queryParameters['size'], '200');
    });
  });
}
