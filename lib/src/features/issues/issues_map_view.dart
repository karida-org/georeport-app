import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../api/models/bundle.dart';
import '../../api/models/geojson.dart';

class IssuesMapView extends StatelessWidget {
  const IssuesMapView({required this.bundle, super.key});

  final Bundle bundle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placed = bundle.placed.toList();

    final markers = <Marker>[];
    final polylines = <Polyline<Object>>[];
    final polygons = <Polygon<Object>>[];
    for (final issue in placed) {
      switch (issue.geometry) {
        case PointGeometry(:final points):
          markers.addAll(
            points.map(
              (point) => Marker(
                point: point,
                width: 40,
                height: 40,
                child: _IssueMarker(issueId: issue.summary.id),
              ),
            ),
          );
        case LineGeometry(:final lines):
          polylines.addAll(
            lines.map(
              (line) =>
                  Polyline(points: line, strokeWidth: 4, color: scheme.primary),
            ),
          );
          markers.add(
            Marker(
              point: issue.geometry!.anchor,
              width: 40,
              height: 40,
              child: _IssueMarker(issueId: issue.summary.id),
            ),
          );
        case PolygonGeometry(:final rings):
          polygons.addAll(
            rings.map(
              (ring) => Polygon(
                points: ring,
                color: scheme.primary.withValues(alpha: 0.15),
                borderColor: scheme.primary,
                borderStrokeWidth: 2,
              ),
            ),
          );
          markers.add(
            Marker(
              point: issue.geometry!.anchor,
              width: 40,
              height: 40,
              child: _IssueMarker(issueId: issue.summary.id),
            ),
          );
        case null:
          break;
      }
    }

    final allPoints = [
      for (final issue in placed) ...issue.geometry!.allPoints,
    ];

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: allPoints.isEmpty
            ? null
            : CameraFit.coordinates(
                coordinates: allPoints,
                padding: const EdgeInsets.all(48),
              ),
        initialCenter: allPoints.isEmpty ? const LatLng(0, 0) : allPoints.first,
        initialZoom: 2,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'org.georeport',
        ),
        PolygonLayer(polygons: polygons),
        PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap contributors'),
        ),
      ],
    );
  }
}

class _IssueMarker extends StatelessWidget {
  const _IssueMarker({required this.issueId});

  final int issueId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/issues/$issueId'),
      child: Icon(
        Icons.place,
        size: 36,
        color: Theme.of(context).colorScheme.primary,
        shadows: const [Shadow(blurRadius: 4, color: Colors.black45)],
      ),
    );
  }
}
