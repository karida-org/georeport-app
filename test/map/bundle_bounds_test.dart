import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/models/bundle.dart';
import 'package:georeport/src/map/bundle_bounds.dart';

void main() {
  test('computes the bounding box over all placed geometries', () {
    final json =
        jsonDecode(File('test/fixtures/bundle.json').readAsStringSync())
            as Map<String, dynamic>;
    final bounds = boundsForBundle(Bundle.fromJson(json));

    expect(bounds, isNotNull);
    expect(bounds!.longitudeWest, lessThan(bounds.longitudeEast));
    expect(bounds.latitudeSouth, lessThan(bounds.latitudeNorth));
  });

  test('returns null when nothing is placed', () {
    final bounds = boundsForBundle(
      Bundle.fromJson({
        'projects': <Object>[],
        'issues': {
          'point': {'type': 'FeatureCollection', 'features': <Object>[]},
          'line': {'type': 'FeatureCollection', 'features': <Object>[]},
          'polygon': {'type': 'FeatureCollection', 'features': <Object>[]},
          'unplaced': <Object>[],
        },
      }),
    );

    expect(bounds, isNull);
  });
}
