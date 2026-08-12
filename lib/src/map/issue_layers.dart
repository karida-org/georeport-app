import 'dart:convert';

import 'package:maplibre/maplibre.dart';

import 'bundle_sources.dart';
import 'issue_style.dart';

/// Style source and layer ids for the issue data, shared between the layer
/// wiring here and the tap handling in the map view.
const issuePointsSource = 'issues-points';
const issueLinesSource = 'issues-lines';
const issuePolygonsSource = 'issues-polygons';

const issueTappableLayers = [
  'issues-points-circle',
  'issues-lines-line',
  'issues-polygons-fill',
];

/// Adds the three GeoJSON sources for a bundle to a freshly loaded style.
Future<void> addIssueSources(
  StyleController style,
  BundleSources sources,
) async {
  await style.addSource(
    GeoJsonSource(id: issuePolygonsSource, data: jsonEncode(sources.polygons)),
  );
  await style.addSource(
    GeoJsonSource(id: issueLinesSource, data: jsonEncode(sources.lines)),
  );
  await style.addSource(
    GeoJsonSource(id: issuePointsSource, data: jsonEncode(sources.points)),
  );
}

/// Replaces the source data after a bundle refresh.
Future<void> updateIssueSources(
  StyleController style,
  BundleSources sources,
) async {
  await style.updateGeoJsonSource(
    id: issuePolygonsSource,
    data: jsonEncode(sources.polygons),
  );
  await style.updateGeoJsonSource(
    id: issueLinesSource,
    data: jsonEncode(sources.lines),
  );
  await style.updateGeoJsonSource(
    id: issuePointsSource,
    data: jsonEncode(sources.points),
  );
}

/// Adds the issue style layers: polygon fill and outline, lines, and the
/// status-colored point circles, all driven by `status_id`.
Future<void> addIssueLayers(StyleController style) async {
  final statusColor = statusColorExpression();
  await style.addLayer(
    FillStyleLayer(
      id: 'issues-polygons-fill',
      sourceId: issuePolygonsSource,
      paint: {'fill-color': statusColor, 'fill-opacity': 0.25},
    ),
  );
  await style.addLayer(
    LineStyleLayer(
      id: 'issues-polygons-outline',
      sourceId: issuePolygonsSource,
      paint: {'line-color': statusColor, 'line-width': 2.0},
    ),
  );
  await style.addLayer(
    LineStyleLayer(
      id: 'issues-lines-line',
      sourceId: issueLinesSource,
      paint: {'line-color': statusColor, 'line-width': 4.0},
    ),
  );
  await style.addLayer(
    CircleStyleLayer(
      id: 'issues-points-circle',
      sourceId: issuePointsSource,
      paint: {
        'circle-radius': 11.0,
        'circle-color': statusColor,
        'circle-stroke-color': '#FFFFFF',
        'circle-stroke-width': 2.0,
      },
    ),
  );
}
