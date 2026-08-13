import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/models/geojson.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('pointFeatureJson', () {
    test('writes a GeoJSON Feature the server can store', () {
      final decoded =
          jsonDecode(pointFeatureJson(const LatLng(35.681236, 139.767125)))
              as Map<String, dynamic>;

      expect(decoded['type'], 'Feature');
      expect(decoded['properties'], isEmpty);
      final geometry = decoded['geometry'] as Map<String, dynamic>;
      expect(geometry['type'], 'Point');
      expect(geometry['coordinates'], [139.767125, 35.681236]);
    });

    test('puts longitude first, which is the opposite of LatLng', () {
      // The single mistake this format invites. Latitude is bounded at 90, so
      // a swapped pair is not merely in the wrong place, it can be invalid.
      final decoded =
          jsonDecode(pointFeatureJson(const LatLng(1.0, 2.0)))
              as Map<String, dynamic>;
      final coordinates =
          (decoded['geometry'] as Map<String, dynamic>)['coordinates'] as List;

      expect(coordinates.first, 2.0, reason: 'longitude comes first');
      expect(coordinates.last, 1.0, reason: 'latitude comes second');
    });

    test('stays valid JSON for negative and high-precision coordinates', () {
      final decoded =
          jsonDecode(pointFeatureJson(const LatLng(-33.8688, -151.2093)))
              as Map<String, dynamic>;
      final coordinates =
          (decoded['geometry'] as Map<String, dynamic>)['coordinates'] as List;

      expect(coordinates, [-151.2093, -33.8688]);
    });
  });
}
