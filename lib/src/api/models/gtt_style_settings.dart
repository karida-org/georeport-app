import 'dart:convert';

/// Instance-defined styling from `/gtt/settings.json`: tracker names and
/// icons, status names and colors. Everything is optional decoration; an
/// instance without the endpoint yields empty maps and the app falls back
/// to neutral styling.
class GttStyleSettings {
  const GttStyleSettings({
    this.trackerNames = const {},
    this.trackerSvgs = const {},
    this.statusNames = const {},
    this.statusColors = const {},
    this.raw = const {},
  });

  factory GttStyleSettings.fromJson(Map<String, dynamic> json) {
    final defaults = json['gttDefaultSetting'];
    if (defaults is! Map<String, dynamic>) {
      return const GttStyleSettings();
    }
    final trackerNames = <int, String>{};
    final trackerSvgs = <int, String>{};
    final icons = defaults['defaultTrackerIcon'];
    if (icons is List) {
      for (final entry in icons) {
        if (entry is! Map<String, dynamic>) {
          continue;
        }
        final id = entry['trackerID'];
        if (id is! num) {
          continue;
        }
        final name = entry['trackerName'];
        if (name is String && name.isNotEmpty) {
          trackerNames[id.toInt()] = name;
        }
        final svg = _iconSvg(entry['icon']);
        if (svg != null) {
          trackerSvgs[id.toInt()] = svg;
        }
      }
    }

    final statusNames = <int, String>{};
    final statusColors = <int, String>{};
    final statuses = defaults['defaultStatusColor'];
    if (statuses is List) {
      for (final entry in statuses) {
        if (entry is! Map<String, dynamic>) {
          continue;
        }
        final id = entry['statusID'];
        if (id is! num) {
          continue;
        }
        final name = entry['statusName'];
        if (name is String && name.isNotEmpty) {
          statusNames[id.toInt()] = name;
        }
        final color = entry['color'];
        if (color is String && color.isNotEmpty) {
          statusColors[id.toInt()] = color;
        }
      }
    }

    return GttStyleSettings(
      raw: json,
      trackerNames: trackerNames,
      trackerSvgs: trackerSvgs,
      statusNames: statusNames,
      statusColors: statusColors,
    );
  }

  final Map<int, String> trackerNames;
  final Map<int, String> trackerSvgs;
  final Map<int, String> statusNames;
  final Map<int, String> statusColors;

  /// The payload this was parsed from, verbatim, for the offline session
  /// cache. Empty for the default (no styling) instance.
  final Map<String, dynamic> raw;

  /// The icon field is a JSON string inside the JSON, holding
  /// `{"id": ..., "svg": "<svg .../>"}`.
  static String? _iconSvg(Object? rawIcon) {
    if (rawIcon is! String || rawIcon.isEmpty) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = json.decode(rawIcon);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final svg = decoded['svg'];
    return svg is String && svg.isNotEmpty ? svg : null;
  }
}
