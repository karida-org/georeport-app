import 'dart:convert';

/// Fallback colors per Redmine status id, used until instance-defined
/// styling is honored. Unknown statuses fall back to the app primary tone.
const Map<int, String> _statusColors = {
  1: '#1E88E5',
  2: '#FB8C00',
  3: '#43A047',
  4: '#8E24AA',
  5: '#757575',
  6: '#546E7A',
};

const String _fallbackColor = '#00695C';

/// A MapLibre style-spec `match` expression coloring features by their
/// `status_id` property.
List<Object> statusColorExpression() => [
  'match',
  ['get', 'status_id'],
  for (final entry in _statusColors.entries) ...[entry.key, entry.value],
  _fallbackColor,
];

/// Extracts per-tracker SVG strings from the raw `/gtt/settings.json`
/// payload. Icons are stored as a JSON string inside the JSON, holding
/// `{"id": ..., "svg": "<svg .../>"}`.
Map<int, String> parseTrackerIconSvgs(Map<String, dynamic> settings) {
  final defaults = settings['gttDefaultSetting'] as Map<String, dynamic>?;
  final icons = defaults?['defaultTrackerIcon'] as List<dynamic>? ?? const [];
  final result = <int, String>{};
  for (final entry in icons) {
    final iconEntry = entry as Map<String, dynamic>;
    final trackerId = (iconEntry['trackerID'] as num?)?.toInt();
    final rawIcon = iconEntry['icon'];
    if (trackerId == null || rawIcon is! String || rawIcon.isEmpty) {
      continue;
    }
    try {
      final icon = json.decode(rawIcon) as Map<String, dynamic>;
      final svg = icon['svg'] as String?;
      if (svg != null && svg.isNotEmpty) {
        result[trackerId] = svg;
      }
    } on FormatException {
      continue;
    }
  }
  return result;
}
