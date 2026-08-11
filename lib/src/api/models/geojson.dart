import 'package:latlong2/latlong.dart';

/// A GeoJSON geometry reduced to what the map needs.
///
/// Z values are dropped for display; MultiPolygon holes are ignored in the
/// spike (outer rings only).
sealed class IssueGeometry {
  const IssueGeometry();

  static IssueGeometry? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    final type = json['type'] as String?;
    final coordinates = json['coordinates'];
    switch (type) {
      case 'Point':
        return PointGeometry([_position(coordinates)]);
      case 'MultiPoint':
        return PointGeometry(_line(coordinates));
      case 'LineString':
        return LineGeometry([_line(coordinates)]);
      case 'MultiLineString':
        return LineGeometry(_lines(coordinates));
      case 'Polygon':
        return PolygonGeometry([_outerRing(coordinates)]);
      case 'MultiPolygon':
        return PolygonGeometry([
          for (final polygon in coordinates as List<dynamic>)
            _outerRing(polygon),
        ]);
      default:
        return null;
    }
  }

  /// A representative point, used to focus the map on this issue.
  LatLng get anchor;

  /// Every vertex, used to compute camera bounds.
  List<LatLng> get allPoints;
}

class PointGeometry extends IssueGeometry {
  const PointGeometry(this.points);

  final List<LatLng> points;

  @override
  LatLng get anchor => points.first;

  @override
  List<LatLng> get allPoints => points;
}

class LineGeometry extends IssueGeometry {
  const LineGeometry(this.lines);

  final List<List<LatLng>> lines;

  @override
  LatLng get anchor => lines.first.first;

  @override
  List<LatLng> get allPoints => [for (final line in lines) ...line];
}

class PolygonGeometry extends IssueGeometry {
  const PolygonGeometry(this.rings);

  final List<List<LatLng>> rings;

  @override
  LatLng get anchor => rings.first.first;

  @override
  List<LatLng> get allPoints => [for (final ring in rings) ...ring];
}

LatLng _position(Object? raw) {
  final position = raw as List<dynamic>;
  return LatLng(
    (position[1] as num).toDouble(),
    (position[0] as num).toDouble(),
  );
}

List<LatLng> _line(Object? raw) {
  return [for (final position in raw as List<dynamic>) _position(position)];
}

List<List<LatLng>> _lines(Object? raw) {
  return [for (final line in raw as List<dynamic>) _line(line)];
}

List<LatLng> _outerRing(Object? raw) {
  final rings = raw as List<dynamic>;
  return _line(rings.first);
}
