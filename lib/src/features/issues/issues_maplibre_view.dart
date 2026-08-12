import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre/maplibre.dart';

import '../../api/models/bundle.dart';
import '../../map/bundle_bounds.dart';
import '../../map/bundle_sources.dart';
import '../../map/issue_layers.dart';
import '../../map/offline_evaluation.dart';
import '../../map/tracker_icons.dart';
import '../connect/connection_provider.dart';

/// Overridable at build time, e.g. for a self-hosted style or a local dev
/// proxy: `flutter run --dart-define=GEOREPORT_MAP_STYLE=<url>`.
const _styleUrl = String.fromEnvironment(
  'GEOREPORT_MAP_STYLE',
  defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
);

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
    if (!identical(oldWidget.bundle, widget.bundle)) {
      final style = _style;
      if (style != null) {
        updateIssueSources(style, bundleToSources(widget.bundle)).catchError(
          (Object error) => debugPrint('Map source refresh failed: $error'),
        );
      }
    }
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    _style = style;
    await addIssueSources(style, bundleToSources(widget.bundle));
    await addIssueLayers(style);
    final connection = ref.read(connectionProvider);
    if (connection != null) {
      await addTrackerIconLayer(style, connection.client);
    }
    await _fitToBundle();
  }

  Future<void> _fitToBundle() async {
    final controller = _controller;
    final bounds = boundsForBundle(widget.bundle);
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
