import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../../../api/models/bundle.dart';
import '../../../api/models/gtt_style_settings.dart';
import '../../../api/models/issue_document.dart';
import '../../../api/models/issue_summary.dart';
import '../../../map/bundle_sources.dart';
import '../../../map/issue_layers.dart';

const _styleUrl = String.fromEnvironment(
  'GEOREPORT_MAP_STYLE',
  defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
);

/// A small, non-interactive map showing one issue's geometry.
class IssueMapSnippet extends StatelessWidget {
  const IssueMapSnippet({required this.issue, this.styleSettings, super.key});

  final IssueDocument issue;
  final GttStyleSettings? styleSettings;

  @override
  Widget build(BuildContext context) {
    final geometry = issue.geometry;
    if (geometry == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 180,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: MapLibreMap(
          options: MapOptions(
            initStyle: _styleUrl,
            initCenter: Geographic(
              lon: geometry.anchor.longitude,
              lat: geometry.anchor.latitude,
            ),
            initZoom: 14,
            gestures: const MapGestures.none(),
          ),
          onStyleLoaded: _onStyleLoaded,
        ),
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    final feature = BundleIssue(
      summary: IssueSummary(
        id: issue.id,
        projectId: issue.project.id,
        subject: issue.subject,
        statusId: issue.status.id,
        trackerId: issue.tracker.id,
        doneRatio: issue.doneRatio,
        lockVersion: issue.lockVersion,
        editable: false,
      ),
      geometry: issue.geometry,
      geometryJson: issue.geometryJson,
    );
    await addIssueSources(style, bundleToSources([feature]));
    await addIssueLayers(style, statusColors: styleSettings?.statusColors);
  }
}
