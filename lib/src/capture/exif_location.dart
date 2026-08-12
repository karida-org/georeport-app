import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:latlong2/latlong.dart';

/// The GPS position embedded in a photo's EXIF, or null when the photo
/// carries none (indoor shots, platforms that strip location on share).
Future<LatLng?> exifLocationOf(Uint8List imageBytes) async {
  final Map<String, IfdTag> tags;
  try {
    tags = await readExifFromBytes(imageBytes);
    // Malformed EXIF can throw Errors (RangeError on truncated segments),
    // not just Exceptions; a photo without usable EXIF is simply untagged.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return null;
  }
  final latitude = _coordinate(
    tags['GPS GPSLatitude'],
    tags['GPS GPSLatitudeRef']?.printable,
    negativeRef: 'S',
  );
  final longitude = _coordinate(
    tags['GPS GPSLongitude'],
    tags['GPS GPSLongitudeRef']?.printable,
    negativeRef: 'W',
  );
  if (latitude == null || longitude == null) {
    return null;
  }
  if (latitude.abs() > 90 || longitude.abs() > 180) {
    return null;
  }
  return LatLng(latitude, longitude);
}

/// EXIF stores coordinates as three rationals (degrees, minutes, seconds)
/// plus a hemisphere reference.
double? _coordinate(IfdTag? tag, String? ref, {required String negativeRef}) {
  final values = tag?.values;
  if (values is! IfdRatios || values.ratios.length < 3) {
    return null;
  }
  final parts = values.ratios;
  // A zero denominator is corrupt data, not a zero coordinate.
  if (parts.take(3).any((ratio) => ratio.denominator == 0)) {
    return null;
  }
  double toDouble(Ratio ratio) => ratio.numerator / ratio.denominator;
  final degrees =
      toDouble(parts[0]) + toDouble(parts[1]) / 60 + toDouble(parts[2]) / 3600;
  final sign = (ref ?? '').trim().toUpperCase() == negativeRef ? -1.0 : 1.0;
  return degrees * sign;
}
