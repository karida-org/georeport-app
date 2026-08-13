import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../api/models/bundle.dart';
import '../../../api/models/project_schema.dart';

/// Step 3: which project, and which tracker within it.
///
/// Changing either clears the custom-field values the caller holds, because
/// the fields themselves change: a value entered for one tracker's field
/// means nothing under another.
class CaptureProjectStep extends StatelessWidget {
  const CaptureProjectStep({
    required this.projects,
    required this.projectId,
    required this.schema,
    required this.trackerId,
    required this.onProjectChanged,
    required this.onTrackerChanged,
    this.enabled = true,
    super.key,
  });

  final List<BundleProject> projects;
  final int projectId;
  final ProjectSchema schema;
  final int? trackerId;
  final ValueChanged<int?> onProjectChanged;
  final ValueChanged<int?> onTrackerChanged;

  /// False while a submission is in flight, so the draft cannot be re-aimed
  /// at another project mid-send.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          initialValue: projectId,
          decoration: InputDecoration(
            labelText: l10n.issueProjectLabel,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final project in projects)
              DropdownMenuItem(value: project.id, child: Text(project.name)),
          ],
          onChanged: enabled ? onProjectChanged : null,
        ),
        const SizedBox(height: 16),
        if (schema.trackers.isEmpty)
          Text(l10n.captureNoTrackers)
        else
          DropdownButtonFormField<int>(
            initialValue: trackerId,
            decoration: InputDecoration(
              labelText: l10n.captureTrackerLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final tracker in schema.trackers)
                DropdownMenuItem(value: tracker.id, child: Text(tracker.name)),
            ],
            onChanged: enabled ? onTrackerChanged : null,
          ),
      ],
    );
  }
}
