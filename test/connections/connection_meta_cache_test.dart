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

    test('clear forgets the snapshot', () async {
      await cache.save(
        'c1',
        capabilities: Capabilities.fromJson(const {'plugin': 'x'}),
        styleSettings: const GttStyleSettings(),
      );
      await cache.clear('c1');
      expect(await cache.load('c1'), isNull);
    });
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
}
