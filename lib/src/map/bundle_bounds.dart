import 'package:maplibre/maplibre.dart';

import '../api/models/bundle.dart';

/// The bounding box of every placed issue, or null when nothing is placed.
LngLatBounds? boundsForBundle(Iterable<BundleIssue> issues) {
  var west = double.infinity;
  var south = double.infinity;
  var east = double.negativeInfinity;
  var north = double.negativeInfinity;
  for (final issue in issues.where((issue) => issue.isPlaced)) {
    for (final point in issue.geometry!.allPoints) {
      west = point.longitude < west ? point.longitude : west;
      east = point.longitude > east ? point.longitude : east;
      south = point.latitude < south ? point.latitude : south;
      north = point.latitude > north ? point.latitude : north;
    }
  }
  if (west > east) {
    return null;
  }
  return LngLatBounds(
    longitudeWest: west,
    longitudeEast: east,
    latitudeSouth: south,
    latitudeNorth: north,
  );
}
