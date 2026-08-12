import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

/// Debug-only evaluation hook for the MapLibre offline story (issue #4):
/// downloads a small region around the camera center into the offline cache
/// and reports tile counts. Real offline support is a roadmap item (M4).
Future<void> downloadRegionForEvaluation({
  required MapController controller,
  required ScaffoldMessengerState messenger,
  required String styleUrl,
}) async {
  messenger.showSnackBar(
    const SnackBar(content: Text('Downloading offline region...')),
  );
  // A small box keeps the evaluation download fast; real offline scoping is
  // an M4 design question.
  final center = controller.getCamera().center;
  final bounds = LngLatBounds(
    longitudeWest: center.lon - 0.15,
    longitudeEast: center.lon + 0.15,
    latitudeSouth: center.lat - 0.1,
    latitudeNorth: center.lat + 0.1,
  );
  debugPrint('[offline] bounds: $bounds, creating manager');
  OfflineManager? manager;
  try {
    manager = await OfflineManager.createInstance();
    debugPrint('[offline] manager ready, starting download');
    DownloadProgress? last;
    await for (final update in manager.downloadRegion(
      mapStyleUrl: styleUrl,
      bounds: bounds,
      minZoom: 8,
      maxZoom: 12,
      pixelDensity: 1,
    )) {
      last = update;
      debugPrint(
        '[offline] ${update.loadedTiles}/${update.totalTiles} tiles, '
        'completed=${update.downloadCompleted}',
      );
      if (update.downloadCompleted) {
        break;
      }
    }
    final regions = await manager.listOfflineRegions();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Offline region ready: ${last?.loadedTiles ?? 0} tiles, '
          '${((last?.loadedBytes ?? 0) / (1024 * 1024)).toStringAsFixed(1)} MB '
          '(${regions.length} region(s) stored)',
        ),
      ),
    );
  } on Exception catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('Offline download failed: $error')),
    );
  } finally {
    manager?.dispose();
  }
}
