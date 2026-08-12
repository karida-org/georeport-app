import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

/// One concern per step, so a report is asked for in the order a worker
/// actually has the answers: what happened, where, which project, the
/// details, then a look before it goes out.
enum CaptureStep { photos, location, project, details, review }

extension CaptureStepLabel on CaptureStep {
  String title(AppLocalizations l10n) => switch (this) {
    CaptureStep.photos => l10n.captureStepPhotos,
    CaptureStep.location => l10n.captureStepLocation,
    CaptureStep.project => l10n.captureStepProject,
    CaptureStep.details => l10n.captureStepDetails,
    CaptureStep.review => l10n.captureStepReview,
  };
}

/// The step rail: which step this is, and how far along. Deliberately a
/// progress line and a title rather than five tappable dots — with one
/// hand in the field, a mis-tap that jumps steps is worse than a Back
/// button.
class CaptureStepHeader extends StatelessWidget {
  const CaptureStepHeader({required this.step, super.key});

  final CaptureStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final index = CaptureStep.values.indexOf(step);
    final total = CaptureStep.values.length;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(step.title(l10n), style: theme.textTheme.titleMedium),
              Text(
                l10n.captureStepCounter(index + 1, total),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: (index + 1) / total),
          ),
        ],
      ),
    );
  }
}

/// Back and forward for the wizard. The forward action carries the step's
/// own label (Next, or Create issue on the last one) so the button always
/// says what it will do.
class CaptureStepControls extends StatelessWidget {
  const CaptureStepControls({
    required this.onBack,
    required this.onNext,
    required this.nextLabel,
    this.busy = false,
    super.key,
  });

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String nextLabel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (onBack != null)
              TextButton(
                onPressed: busy ? null : onBack,
                child: Text(l10n.captureStepBack),
              ),
            const Spacer(),
            FilledButton(
              onPressed: busy ? null : onNext,
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(nextLabel),
            ),
          ],
        ),
      ),
    );
  }
}
