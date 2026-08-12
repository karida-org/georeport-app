import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'settings_widgets.dart';

final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

/// Version, license, source, and the aggregated licenses of everything the
/// app is built from. Source availability is a GPL obligation once binaries
/// ship, so the repository link is more than a courtesy.
class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  static final _repositoryUrl = Uri.parse(
    'https://github.com/karida-org/georeport-app',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final info = ref.watch(packageInfoProvider).value;
    final version = info == null ? '' : '${info.version} (${info.buildNumber})';
    return SettingsSection(
      title: l10n.settingsAboutHeading,
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.appTitle),
          subtitle: Text(
            '${l10n.settingsVersion(version)}\n${l10n.settingsLicenseLine}',
          ),
          isThreeLine: true,
        ),
        ListTile(
          leading: const Icon(Icons.code),
          title: Text(l10n.settingsSourceCode),
          subtitle: Text(_repositoryUrl.toString()),
          onTap: () =>
              launchUrl(_repositoryUrl, mode: LaunchMode.externalApplication),
        ),
        ListTile(
          leading: const Icon(Icons.collections_bookmark_outlined),
          title: Text(l10n.settingsOssLicenses),
          onTap: () => showLicensePage(
            context: context,
            applicationName: l10n.appTitle,
            applicationVersion: info?.version,
          ),
        ),
      ],
    );
  }
}
