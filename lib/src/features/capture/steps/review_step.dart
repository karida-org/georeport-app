import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../capture/issue_draft.dart';
import '../capture_widgets.dart';

/// Step 5: what is about to be sent, in plain lines.
///
/// Deliberately a summary of values rather than a second set of editors: the
/// point of the step is to read back what was entered, on a screen someone
/// may be looking at in bright sunlight before committing.
class CaptureReviewStep extends StatelessWidget {
  const CaptureReviewStep({
    required this.photos,
    required this.subject,
    required this.projectName,
    required this.trackerName,
    required this.location,
    required this.description,
    super.key,
  });

  final List<DraftPhoto> photos;

  /// Already trimmed; empty means the required subject is still missing.
  final String subject;
  final String? projectName;
  final String? trackerName;
  final LatLng? location;

  /// Already trimmed; empty rows are left out rather than shown blank.
  final String description;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (photos.isNotEmpty) ...[
          CapturePhotoStrip(photos: photos),
          const SizedBox(height: 16),
        ],
        _ReviewRow(
          label: l10n.captureSubjectLabel,
          value: subject.isEmpty ? l10n.captureSubjectRequired : subject,
        ),
        if (projectName case final String name)
          _ReviewRow(label: l10n.issueProjectLabel, value: name),
        if (trackerName case final String name)
          _ReviewRow(label: l10n.captureTrackerLabel, value: name),
        _ReviewRow(
          label: l10n.captureStepLocation,
          value: location == null
              ? l10n.captureNoLocation
              : '${location!.latitude.toStringAsFixed(5)}, '
                    '${location!.longitude.toStringAsFixed(5)}',
        ),
        if (description.isNotEmpty)
          _ReviewRow(label: l10n.captureDescriptionLabel, value: description),
      ],
    );
  }
}

/// One labelled line of the review summary.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
