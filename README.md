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

Without a phone or simulator, `flutter run -d chrome` works for day-to-day
development (the web target exists for that purpose; mobile stays the
product). To try it against a live instance, run
`dart run tool/live_check.dart <base-url> <api-key>` first to confirm the
server side, and note that browsers need the Redmine instance to send CORS
headers, which stock Redmine does not; a phone or simulator has no such
restriction.

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

Distribution through app stores whose terms conflict with the plain GPL
(notably the Apple App Store) is covered by an additional permission under
GPLv3 section 7: see
[LICENSE-APPSTORE-EXCEPTION](LICENSE-APPSTORE-EXCEPTION). Contributions
are accepted under GPL-3.0-or-later including this additional permission.
