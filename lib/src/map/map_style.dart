/// The MapLibre style every map in the app renders with.
///
/// Overridable at build time, e.g. for a self-hosted style or a local dev
/// proxy: `flutter run --dart-define=GEOREPORT_MAP_STYLE=<url>`.
///
/// One declaration on purpose. Anyone pointing the app at their own tile
/// server should have a single place to look.
const mapStyleUrl = String.fromEnvironment(
  'GEOREPORT_MAP_STYLE',
  defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
);
