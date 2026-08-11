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
    final sources = bundleToSources(Bundle.fromJson(json));

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
}
