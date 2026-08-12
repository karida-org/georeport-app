import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre/maplibre.dart';

import '../../api/models/bundle.dart';
import '../../map/bundle_sources.dart';
import '../../map/issue_style.dart';
import '../../map/svg_raster.dart';
import '../connect/connection_provider.dart';

/// Overridable at build time, e.g. for a self-hosted style or a local dev
/// proxy: `flutter run --dart-define=GEOREPORT_MAP_STYLE=<url>`.
const _styleUrl = String.fromEnvironment(
  'GEOREPORT_MAP_STYLE',
  defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
);

const _pointsSource = 'issues-points';
const _linesSource = 'issues-lines';
const _polygonsSource = 'issues-polygons';
const _tappableLayers = [
  'issues-points-circle',
  'issues-lines-line',
  'issues-polygons-fill',
];

class IssuesMapLibreView extends ConsumerStatefulWidget {
  const IssuesMapLibreView({required this.bundle, super.key});

  final Bundle bundle;

  @override
  ConsumerState<IssuesMapLibreView> createState() => _IssuesMapLibreViewState();
}

class _IssuesMapLibreViewState extends ConsumerState<IssuesMapLibreView> {
  MapController? _controller;
  StyleController? _style;

  @override
  Widget build(BuildContext context) {
    final map = MapLibreMap(
      options: const MapOptions(
        initStyle: _styleUrl,
        initCenter: Geographic(lon: 137.0, lat: 37.0),
        initZoom: 3,
      ),
      onMapCreated: (controller) => _controller = controller,
      onStyleLoaded: _onStyleLoaded,
      onEvent: _onEvent,
      children: const [SourceAttribution()],
    );
    if (!kDebugMode) {
      return map;
    }
    return Stack(
      children: [
        map,
        Positioned(
          left: 8,
          bottom: 8,
          child: IconButton.filledTonal(
            icon: const Icon(Icons.download_for_offline),
            tooltip: 'Dev: download visible region for offline use',
            onPressed: _downloadVisibleRegion,
          ),
        ),
      ],
    );
  }

  /// Debug-only evaluation hook for the MapLibre offline story (issue #4):
  /// downloads the currently visible region into the offline cache and
  /// reports tile counts. Real offline support is a roadmap item (M4).
  Future<void> _downloadVisibleRegion() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Downloading offline region...')),
    );
    // A small box around the camera center keeps the evaluation download
    // fast; real offline scoping is an M4 design question.
    final center = controller.getCamera().center;
    final bounds = LngLatBounds(
      longitudeWest: center.lon - 0.15,
      longitudeEast: center.lon + 0.15,
      latitudeSouth: center.lat - 0.1,
      latitudeNorth: center.lat + 0.1,
    );
    debugPrint('[offline] bounds: $bounds, creating manager');
    final manager = await OfflineManager.createInstance();
    debugPrint('[offline] manager ready, starting download');
    try {
      DownloadProgress? last;
      await for (final update in manager.downloadRegion(
        mapStyleUrl: _styleUrl,
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
      manager.dispose();
    }
  }

  @override
  void didUpdateWidget(IssuesMapLibreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bundle, widget.bundle)) {
      _updateSources();
    }
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    _style = style;
    final sources = bundleToSources(widget.bundle);
    await style.addSource(
      GeoJsonSource(id: _polygonsSource, data: jsonEncode(sources.polygons)),
    );
    await style.addSource(
      GeoJsonSource(id: _linesSource, data: jsonEncode(sources.lines)),
    );
    await style.addSource(
      GeoJsonSource(id: _pointsSource, data: jsonEncode(sources.points)),
    );

    final statusColor = statusColorExpression();
    await style.addLayer(
      FillStyleLayer(
        id: 'issues-polygons-fill',
        sourceId: _polygonsSource,
        paint: {'fill-color': statusColor, 'fill-opacity': 0.25},
      ),
    );
    await style.addLayer(
      LineStyleLayer(
        id: 'issues-polygons-outline',
        sourceId: _polygonsSource,
        paint: {'line-color': statusColor, 'line-width': 2.0},
      ),
    );
    await style.addLayer(
      LineStyleLayer(
        id: 'issues-lines-line',
        sourceId: _linesSource,
        paint: {'line-color': statusColor, 'line-width': 4.0},
      ),
    );
    await style.addLayer(
      CircleStyleLayer(
        id: 'issues-points-circle',
        sourceId: _pointsSource,
        paint: {
          'circle-radius': 11.0,
          'circle-color': statusColor,
          'circle-stroke-color': '#FFFFFF',
          'circle-stroke-width': 2.0,
        },
      ),
    );
    await _addTrackerIcons(style);
    await _fitToBundle();
  }

  /// Tracker icons are decoration on top of the status circles; any failure
  /// (endpoint missing, SVG quirks) leaves the circles fully functional.
  Future<void> _addTrackerIcons(StyleController style) async {
    final connection = ref.read(connectionProvider);
    if (connection == null) {
      return;
    }
    try {
      final settings = await connection.client.gttSettings();
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
          sourceId: _pointsSource,
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

  Future<void> _updateSources() async {
    final style = _style;
    if (style == null) {
      return;
    }
    final sources = bundleToSources(widget.bundle);
    await style.updateGeoJsonSource(
      id: _polygonsSource,
      data: jsonEncode(sources.polygons),
    );
    await style.updateGeoJsonSource(
      id: _linesSource,
      data: jsonEncode(sources.lines),
    );
    await style.updateGeoJsonSource(
      id: _pointsSource,
      data: jsonEncode(sources.points),
    );
  }

  Future<void> _fitToBundle() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    var west = double.infinity;
    var south = double.infinity;
    var east = double.negativeInfinity;
    var north = double.negativeInfinity;
    for (final issue in widget.bundle.placed) {
      for (final point in issue.geometry!.allPoints) {
        west = point.longitude < west ? point.longitude : west;
        east = point.longitude > east ? point.longitude : east;
        south = point.latitude < south ? point.latitude : south;
        north = point.latitude > north ? point.latitude : north;
      }
    }
    if (west > east) {
      return;
    }
    await controller.fitBounds(
      bounds: LngLatBounds(
        longitudeWest: west,
        longitudeEast: east,
        latitudeSouth: south,
        latitudeNorth: north,
      ),
      padding: const EdgeInsets.all(48),
    );
  }

  void _onEvent(MapEvent event) {
    if (event is! MapEventClick) {
      return;
    }
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final features = controller.featuresInRect(
      Rect.fromCircle(center: event.screenPoint, radius: 14),
      layerIds: _tappableLayers,
    );
    if (features.isEmpty) {
      return;
    }
    // Feature ids are unreliable across platforms (stringified on Android,
    // lossy on web), so the issue id rides in the properties.
    final id = int.tryParse('${features.first.properties['id']}');
    if (id != null && mounted) {
      context.go('/issues/$id');
    }
  }
}
