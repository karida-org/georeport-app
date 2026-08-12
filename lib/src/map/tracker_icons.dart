import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../api/gtt_sync_client.dart';
import 'issue_layers.dart';
import 'issue_style.dart';
import 'svg_raster.dart';

/// Fetches the instance's per-tracker SVG icons, rasterizes them, and adds a
/// symbol layer that draws them on top of the status circles.
///
/// Icons are decoration; any failure (endpoint missing, malformed payload,
/// SVG quirks) is swallowed so the circles stay fully functional.
Future<void> addTrackerIconLayer(
  StyleController style,
  GttSyncClient client,
) async {
  try {
    final settings = await client.gttSettings();
    final svgs = parseTrackerIconSvgs(settings);
    if (svgs.isEmpty) {
      return;
    }
    final images = <String, Uint8List>{};
    for (final entry in svgs.entries) {
      images['tracker-${entry.key}'] = await rasterizeSvg(
        entry.value,
        size: 32,
        color: Colors.white,
      );
    }
    await style.addImages(images);
    await style.addLayer(
      const SymbolStyleLayer(
        id: 'issues-points-icon',
        sourceId: issuePointsSource,
        layout: {
          'icon-image': [
            'concat',
            'tracker-',
            [
              'to-string',
              ['get', 'tracker_id'],
            ],
          ],
          'icon-size': 0.45,
          'icon-allow-overlap': true,
        },
      ),
    );
  } on Exception catch (error) {
    debugPrint('Tracker icons unavailable: $error');
  }
}
