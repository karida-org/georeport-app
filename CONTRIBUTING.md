# Contributing

Thanks for your interest in Georeport.

## Workflow

- **Issue first.** Every change starts as a GitHub issue, so scope and
  approach can be discussed before code exists. Small fixes are fine as
  small issues.
- **Pull requests only.** Nothing lands on `main` directly. Reference the
  issue from the PR description (for example `Closes #12`).
- **Milestones** track the roadmap; see
  [issue #1](https://github.com/karida-org/georeport-app/issues/1) for the
  overview.

## Before you push

Run what CI runs:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

## Conventions

- Keep files small and focused; split modules rather than growing one file.
- User-facing strings go through localization: add every new key to both
  `lib/l10n/app_en.arb` and `lib/l10n/app_ja.arb` in the same change. If a
  Japanese translation is not ready, copy the English value so the key
  exists; the parity test fails on missing keys, not on translation quality.
- The app talks only to the `redmine_gtt_sync` contract. Feature-detect via
  the capabilities probe and degrade gracefully rather than assuming server
  versions.
- GitHub Actions in workflows are pinned to commit SHAs with a version
  comment (`pinact` maintains this; Dependabot keeps the pins fresh).
