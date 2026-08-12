# Georeport brand assets

Source images for the generated launcher icons and splash screens. The
runtime vector marks live in `assets/brand/` (bundled with the app); the
Material themes live in `lib/src/theme.dart`.

## Regenerating icons and splash

Both generators read their configuration from `pubspec.yaml`:

```bash
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

Note: `flutter_launcher_icons` is known to overwrite the boolean
`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` build setting
in `ios/Runner.xcodeproj/project.pbxproj` with `AppIcon`; restore it to
`YES` after regenerating.

`app-icon-play-512.png` is the Play Store listing icon; it is not used by
the generators.

## Usage rules

- The red dot means "a report": it appears in the logo and on map markers
  only. Buttons, links, and selection states stay green.
- Keep clearspace of one dot-diameter around the mark.
- Typography is IBM Plex Sans with IBM Plex Sans JP as the fallback family
  (both SIL OFL, bundled under `fonts/` with the license).
