import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import 'issue_layers.dart';
import 'svg_raster.dart';

/// Rasterizes the instance's per-tracker SVG icons and adds a symbol layer
/// that draws them on top of the status circles.
///
/// Icons are decoration; any failure (no icons configured, SVG quirks)
/// leaves the circles fully functional.
Future<void> addTrackerIconLayer(
  StyleController style,
  Map<int, String> trackerSvgs,
) async {
  if (trackerSvgs.isEmpty) {
    return;
  }
  try {
    final images = <String, Uint8List>{};
    for (final entry in trackerSvgs.entries) {
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
