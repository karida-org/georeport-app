/// Fallback colors per Redmine status id, used when the instance does not
/// define its own. Unknown statuses fall back to the app primary tone.
const Map<int, String> _fallbackStatusColors = {
  1: '#1E88E5',
  2: '#FB8C00',
  3: '#43A047',
  4: '#8E24AA',
  5: '#757575',
  6: '#546E7A',
};

const String _fallbackColor = '#00695C';

/// A MapLibre style-spec `match` expression coloring features by their
/// `status_id` property. Instance-defined colors win over the fallbacks.
List<Object> statusColorExpression([Map<int, String> serverColors = const {}]) {
  final colors = {..._fallbackStatusColors, ...serverColors};
  return [
    'match',
    ['get', 'status_id'],
    for (final entry in colors.entries) ...[entry.key, entry.value],
    _fallbackColor,
  ];
}

/// The effective display color for one status, as `#rrggbb`.
String statusColorFor(
  int statusId, [
  Map<int, String> serverColors = const {},
]) {
  return serverColors[statusId] ??
      _fallbackStatusColors[statusId] ??
      _fallbackColor;
}
