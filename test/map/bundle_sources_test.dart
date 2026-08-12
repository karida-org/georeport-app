import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/models/bundle.dart';
import 'package:georeport/src/map/bundle_sources.dart';

void main() {
  test('rebuilds feature collections with style properties', () {
    final json =
        jsonDecode(File('test/fixtures/bundle.json').readAsStringSync())
            as Map<String, dynamic>;
    final sources = bundleToSources(Bundle.fromJson(json).issues);

    expect(sources.points['features'] as List<dynamic>, hasLength(2));
    expect(sources.lines['features'] as List<dynamic>, hasLength(1));
    expect(sources.polygons['features'] as List<dynamic>, hasLength(1));

    final feature =
        (sources.points['features'] as List<dynamic>).first
            as Map<String, dynamic>;
    final properties = feature['properties'] as Map<String, dynamic>;
    expect(properties['id'], isA<int>());
    expect(properties['status_id'], isA<int>());
    expect(properties['tracker_id'], isA<int>());
    expect(properties['subject'], isA<String>());
    expect(
      (feature['geometry'] as Map<String, dynamic>)['type'],
      anyOf('Point', 'MultiPoint'),
    );
  });

  test('preserves the raw geometry object exactly, including holes', () {
    final geometry = {
      'type': 'MultiPolygon',
      'coordinates': [
        [
          [
            [139.0, 35.0],
            [139.2, 35.0],
            [139.2, 35.2],
            [139.0, 35.2],
            [139.0, 35.0],
          ],
          [
            [139.05, 35.05],
            [139.15, 35.05],
            [139.15, 35.15],
            [139.05, 35.15],
            [139.05, 35.05],
          ],
        ],
      ],
    };
    final bundle = Bundle.fromJson({
      'projects': <Object>[],
      'issues': {
        'point': {'type': 'FeatureCollection', 'features': <Object>[]},
        'line': {'type': 'FeatureCollection', 'features': <Object>[]},
        'polygon': {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'id': 7,
              'geometry': geometry,
              'properties': {
                'id': 7,
                'project_id': 1,
                'subject': 'With hole',
                'status_id': 1,
                'tracker_id': 1,
                'done_ratio': 0,
                'lock_version': 0,
                'editable': true,
              },
            },
          ],
        },
        'unplaced': <Object>[],
      },
    });

    final sources = bundleToSources(bundle.issues);
    final feature =
        (sources.polygons['features'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(feature['geometry'], equals(geometry));
  });
}
