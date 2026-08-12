import 'package:maplibre/maplibre.dart';

/// What a completed region download amounts to.
class OfflineRegionResult {
  const OfflineRegionResult({required this.tiles, required this.bytes});

  final int tiles;
  final int bytes;

  double get megabytes => bytes / (1024 * 1024);
}

/// Downloads the area around the current camera into MapLibre's offline
/// cache, so the basemap keeps rendering there without a network. Zoom is
/// capped: street-level detail for a work area, not a bulk tile scrape.
Future<OfflineRegionResult> downloadCurrentRegion({
  required MapController controller,
  required String styleUrl,
}) async {
  final center = controller.getCamera().center;
  final bounds = LngLatBounds(
    longitudeWest: center.lon - 0.15,
    longitudeEast: center.lon + 0.15,
    latitudeSouth: center.lat - 0.1,
    latitudeNorth: center.lat + 0.1,
  );
  final manager = await OfflineManager.createInstance();
  try {
    DownloadProgress? last;
    await for (final update in manager.downloadRegion(
      mapStyleUrl: styleUrl,
      bounds: bounds,
      minZoom: 8,
      maxZoom: 14,
      pixelDensity: 1,
    )) {
      last = update;
      if (update.downloadCompleted) {
        break;
      }
    }
    return OfflineRegionResult(
      tiles: last?.loadedTiles ?? 0,
      bytes: last?.loadedBytes ?? 0,
    );
  } finally {
    manager.dispose();
  }
}

/// How many regions are stored on this device.
Future<int> storedRegionCount() async {
  final manager = await OfflineManager.createInstance();
  try {
    return (await manager.listOfflineRegions()).length;
  } finally {
    manager.dispose();
  }
}

/// Removes every stored region (the cache is re-downloadable at will).
Future<void> removeStoredRegions() async {
  final manager = await OfflineManager.createInstance();
  try {
    for (final region in await manager.listOfflineRegions()) {
      await manager.deleteRegion(regionId: region.id);
    }
  } finally {
    manager.dispose();
  }
}
