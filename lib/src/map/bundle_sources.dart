import '../api/models/bundle.dart';

/// The three GeoJSON FeatureCollections a map style consumes, mirroring the
/// bundle's point/line/polygon split.
class BundleSources {
  const BundleSources({
    required this.points,
    required this.lines,
    required this.polygons,
  });

  final Map<String, dynamic> points;
  final Map<String, dynamic> lines;
  final Map<String, dynamic> polygons;
}

/// Rebuilds GeoJSON FeatureCollections from parsed bundle issues, keeping
/// the original geometry objects and exposing the properties the style needs
/// for data-driven expressions and tap handling.
BundleSources bundleToSources(Iterable<BundleIssue> bundleIssues) {
  final points = <Map<String, dynamic>>[];
  final lines = <Map<String, dynamic>>[];
  final polygons = <Map<String, dynamic>>[];

  for (final issue in bundleIssues) {
    final geometry = issue.geometryJson;
    if (geometry == null) {
      continue;
    }
    final feature = {
      'type': 'Feature',
      'id': issue.summary.id,
      'geometry': geometry,
      'properties': {
        'id': issue.summary.id,
        'subject': issue.summary.subject,
        'status_id': issue.summary.statusId,
        'tracker_id': issue.summary.trackerId,
      },
    };
    switch (geometry['type']) {
      case 'Point' || 'MultiPoint':
        points.add(feature);
      case 'LineString' || 'MultiLineString':
        lines.add(feature);
      case 'Polygon' || 'MultiPolygon':
        polygons.add(feature);
    }
  }

  Map<String, dynamic> collection(List<Map<String, dynamic>> features) => {
    'type': 'FeatureCollection',
    'features': features,
  };

  return BundleSources(
    points: collection(points),
    lines: collection(lines),
    polygons: collection(polygons),
  );
}
