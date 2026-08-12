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
///
/// The payload is server-controlled decoration, so every shape is validated
/// and anything unexpected is skipped rather than thrown.
Map<int, String> parseTrackerIconSvgs(Map<String, dynamic> settings) {
  final defaults = settings['gttDefaultSetting'];
  if (defaults is! Map<String, dynamic>) {
    return const {};
  }
  final icons = defaults['defaultTrackerIcon'];
  if (icons is! List) {
    return const {};
  }
  final result = <int, String>{};
  for (final entry in icons) {
    if (entry is! Map<String, dynamic>) {
      continue;
    }
    final trackerId = entry['trackerID'];
    final rawIcon = entry['icon'];
    if (trackerId is! num || rawIcon is! String || rawIcon.isEmpty) {
      continue;
    }
    Object? decoded;
    try {
      decoded = json.decode(rawIcon);
    } on FormatException {
      continue;
    }
    if (decoded is! Map<String, dynamic>) {
      continue;
    }
    final svg = decoded['svg'];
    if (svg is String && svg.isNotEmpty) {
      result[trackerId.toInt()] = svg;
    }
  }
  return result;
}
