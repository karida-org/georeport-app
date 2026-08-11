# Georeport

A cross-platform mobile app for [GTT-Redmine](https://github.com/gtt-project):
capture issues from photos in the field and work on assigned issues with a
map, status updates, and time tracking.

Status: early development. The roadmap and architecture overview live in
[issue #1](https://github.com/karida-org/georeport-app/issues/1).

## What it talks to

The app is a client of the `redmine_gtt_sync` server plugin contract (which
builds on `redmine_gtt`). A Redmine instance needs both plugins installed,
the GTT Sync module enabled on a project, and the Use GTT Sync permission
granted, for the app to connect.

## Development

Requirements: Flutter 3.44 or newer on the stable channel (the CI pin is in
`.github/workflows/ci.yml`).

```sh
flutter pub get
flutter run
```

Checks, as run by CI:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Localization: user-facing strings live in `lib/l10n/app_en.arb` (template)
and `lib/l10n/app_ja.arb`. Add every new key to both files; a test enforces
key parity. The generated Dart bindings under `lib/l10n/generated/` are
created by `flutter pub get` and are not committed.

## Contributing

Issue-first: every change starts as a GitHub issue and lands via pull
request. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
