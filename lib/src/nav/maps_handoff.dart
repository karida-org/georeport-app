import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/models/geojson.dart';

/// A representative coordinate for handing an issue's location to a maps
/// app: the point itself, or the first vertex of a line/polygon (navigation
/// needs somewhere to drive to, not a centroid of the whole works area).
LatLng? representativePoint(IssueGeometry? geometry) {
  return switch (geometry) {
    PointGeometry(points: [final first, ...]) => first,
    LineGeometry(lines: [[final first, ...], ...]) => first,
    PolygonGeometry(rings: [[final first, ...], ...]) => first,
    _ => null,
  };
}

/// The platform's directions URL: Apple Maps on iOS, Google Maps elsewhere
/// (the https form falls back to the browser when no maps app is present).
Uri directionsUrl(LatLng destination, {bool? apple}) {
  final isApple = apple ?? Platform.isIOS;
  final coords = '${destination.latitude},${destination.longitude}';
  return isApple
      ? Uri.parse('https://maps.apple.com/?daddr=$coords&dirflg=d')
      : Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$coords');
}

/// Opens turn-by-turn navigation toward the destination in the platform
/// maps app. Returns false when nothing could handle the URL.
Future<bool> launchDirections(LatLng destination) {
  return launchUrl(
    directionsUrl(destination),
    mode: LaunchMode.externalApplication,
  );
}
