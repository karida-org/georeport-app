import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/capture/exif_location.dart';

void main() {
  test('extracts the GPS position from a geotagged photo', () async {
    final bytes = File('test/fixtures/geotagged.jpg').readAsBytesSync();
    final location = await exifLocationOf(bytes);

    expect(location, isNotNull);
    expect(location!.latitude, closeTo(34.6864, 0.0005));
    expect(location.longitude, closeTo(135.1959, 0.0005));
  });

  test('returns null for an image without GPS tags', () async {
    final bytes = File('web/icons/Icon-192.png').readAsBytesSync();
    expect(await exifLocationOf(bytes), isNull);
  });
}
