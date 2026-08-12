import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre/maplibre.dart';

import '../../api/models/bundle.dart';
import '../../api/models/gtt_style_settings.dart';
import '../../map/bundle_bounds.dart';
import '../../map/bundle_sources.dart';
import '../../map/issue_layers.dart';
import '../../map/offline_evaluation.dart';
import '../../map/tracker_icons.dart';

/// Overridable at build time, e.g. for a self-hosted style or a local dev
/// proxy: `flutter run --dart-define=GEOREPORT_MAP_STYLE=<url>`.
const _styleUrl = String.fromEnvironment(
  'GEOREPORT_MAP_STYLE',
  defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
);

class IssuesMapLibreView extends StatefulWidget {
  const IssuesMapLibreView({
    required this.issues,
    this.styleSettings,
    super.key,
  });

  final List<BundleIssue> issues;
  final GttStyleSettings? styleSettings;

  @override
  State<IssuesMapLibreView> createState() => _IssuesMapLibreViewState();
}

class _IssuesMapLibreViewState extends State<IssuesMapLibreView> {
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
            tooltip: 'Dev: download an offline region for evaluation',
            onPressed: () {
              final controller = _controller;
              if (controller != null) {
                downloadRegionForEvaluation(
                  controller: controller,
                  messenger: ScaffoldMessenger.of(context),
                  styleUrl: _styleUrl,
                );
              }
            },
          ),
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(IssuesMapLibreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent rebuilds the filtered list every frame, so identity is not
    // a change signal; a content signature (id + lock_version + placement)
    // is, and it is cheap compared to re-encoding the GeoJSON sources.
    if (_signature(oldWidget.issues) != _signature(widget.issues)) {
      final style = _style;
      if (style != null) {
        updateIssueSources(style, bundleToSources(widget.issues)).catchError(
          (Object error) => debugPrint('Map source refresh failed: $error'),
        );
      }
    }
  }

  static int _signature(List<BundleIssue> issues) {
    return Object.hashAll([
      for (final issue in issues)
        Object.hash(
          issue.summary.id,
          issue.summary.lockVersion,
          issue.isPlaced,
        ),
    ]);
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    _style = style;
    final settings = widget.styleSettings;
    await addIssueSources(style, bundleToSources(widget.issues));
    await addIssueLayers(style, statusColors: settings?.statusColors);
    await addTrackerIconLayer(style, settings?.trackerSvgs ?? const {});
    await _fitToIssues();
  }

  Future<void> _fitToIssues() async {
    final controller = _controller;
    final bounds = boundsForBundle(widget.issues);
    if (controller == null || bounds == null) {
      return;
    }
    await controller.fitBounds(
      bounds: bounds,
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
      layerIds: issueTappableLayers,
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
