import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/models/capabilities.dart';
import 'package:georeport/src/api/models/current_user.dart';
import 'package:georeport/src/api/models/gtt_style_settings.dart';
import 'package:georeport/src/connections/connection_meta_cache.dart';

void main() {
  group('ConnectionMetaCache', () {
    late Directory temp;
    late ConnectionMetaCache cache;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('meta-cache-test');
      cache = ConnectionMetaCache(temp);
    });

    tearDown(() => temp.delete(recursive: true));

    test('a saved session snapshot comes back whole', () async {
      await cache.save(
        'c1',
        capabilities: Capabilities.fromJson({
          'plugin': 'redmine_gtt_sync',
          'version': '0.5.0',
          'redmine': {'version': '7.0.0.stable'},
          'capabilities': {'bundle': true, 'time_entries': true},
        }),
        styleSettings: GttStyleSettings.fromJson(const {}),
        currentUser: CurrentUser.fromJson({
          'user': {'id': 1, 'firstname': 'Site', 'lastname': 'Administrator'},
        }),
      );

      final meta = await cache.load('c1');
      expect(meta, isNotNull);
      expect(meta!.capabilities.redmineVersion, '7.0.0.stable');
      expect(meta.capabilities.supports('time_entries'), isTrue);
      expect(meta.currentUser?.displayName, 'Site Administrator');
      expect(await cache.load('other'), isNull);
    });

    test('clear forgets the snapshot and a leftover write sidecar', () async {
      await cache.save(
        'c1',
        capabilities: Capabilities.fromJson(const {'plugin': 'x'}),
        styleSettings: const GttStyleSettings(),
      );
      final sidecar = File('${temp.path}/connection-meta-c1.json.tmp');
      await sidecar.writeAsString('interrupted write');

      await cache.clear('c1');

      expect(await cache.load('c1'), isNull);
      expect(await sidecar.exists(), isFalse);
    });

    test('a fallback identity is neither persisted nor resurrected', () async {
      await cache.save(
        'c1',
        capabilities: Capabilities.fromJson(const {'plugin': 'x'}),
        styleSettings: const GttStyleSettings(),
        // The parser fallback: no usable identity, empty raw payload.
        currentUser: CurrentUser.fromJson(const {}),
      );
      final meta = await cache.load('c1');
      expect(meta, isNotNull);
      expect(meta!.currentUser, isNull);
    });

    test(
      'a malformed shape loads as null instead of failing the resume',
      () async {
        await File(
          '${temp.path}/connection-meta-c1.json',
        ).writeAsString('{"version": 1, "capabilities": [1, 2]}');
        expect(await cache.load('c1'), isNull);
      },
    );
  });

  group('isUnreachableError', () {
    RequestOptions options() => RequestOptions(path: '/gtt_sync/capabilities');

    test('network-level failures are bridgeable', () {
      expect(
        isUnreachableError(
          DioException(
            requestOptions: options(),
            type: DioExceptionType.connectionError,
          ),
        ),
        isTrue,
      );
      expect(
        isUnreachableError(
          DioException(
            requestOptions: options(),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
        isTrue,
      );
      expect(
        isUnreachableError(
          DioException(
            requestOptions: options(),
            type: DioExceptionType.unknown,
            error: const SocketException('unreachable'),
          ),
        ),
        isTrue,
      );
    });

    test('a server that answered is never bridged', () {
      expect(
        isUnreachableError(
          DioException(
            requestOptions: options(),
            type: DioExceptionType.badResponse,
            response: Response(requestOptions: options(), statusCode: 500),
          ),
        ),
        isFalse,
      );
      expect(isUnreachableError(StateError('no credentials')), isFalse);
    });
  });

  group('mayWriteConnectionMeta', () {
    test('writes for a connection that is still saved', () {
      expect(
        mayWriteConnectionMeta(
          connectionId: 'a',
          savedIds: const ['a', 'b'],
          isNewConnection: false,
        ),
        isTrue,
      );
    });

    test('skips a connection removed while its metadata was fetched', () {
      expect(
        mayWriteConnectionMeta(
          connectionId: 'a',
          savedIds: const ['b'],
          isNewConnection: false,
        ),
        isFalse,
      );
    });

    test('writes for a new connection, which is not saved yet', () {
      // Regression: a first connection is committed only after its metadata
      // is fetched, so it is absent from the saved list at this point. It
      // used to be skipped, leaving a fresh install with no snapshot to
      // resume from offline.
      expect(
        mayWriteConnectionMeta(
          connectionId: 'a',
          savedIds: const <String>[],
          isNewConnection: true,
        ),
        isTrue,
      );
    });

    test('writes while the saved list is still loading', () {
      expect(
        mayWriteConnectionMeta(
          connectionId: 'a',
          savedIds: null,
          isNewConnection: false,
        ),
        isTrue,
      );
    });
  });
}
