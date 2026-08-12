import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../capture/capture_defaults.dart';
import '../issues/issues_store.dart';
import 'settings_widgets.dart';

/// What capture remembers (last project, per-project tracker) and the way
/// to make it forget.
class CaptureDefaultsSection extends ConsumerWidget {
  const CaptureDefaultsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lastProjectId = ref.watch(lastProjectProvider).value;
    final projects = ref.watch(issuesProvider).value?.projects ?? const [];
    final projectName = lastProjectId == null
        ? null
        : projects
              .where((project) => project.id == lastProjectId)
              .map((project) => project.name)
              .firstOrNull;
    return SettingsSection(
      title: l10n.settingsCaptureHeading,
      children: [
        ListTile(
          leading: const Icon(Icons.restore),
          title: Text(l10n.settingsCaptureReset),
          subtitle: Text(
            projectName == null
                ? l10n.settingsCaptureNothingRemembered
                : l10n.settingsCaptureLastProject(projectName),
          ),
          onTap: lastProjectId == null
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await ref.read(captureDefaultsProvider).clear();
                  ref.invalidate(lastProjectProvider);
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.settingsCaptureResetDone)),
                  );
                },
        ),
      ],
    );
  }
}
