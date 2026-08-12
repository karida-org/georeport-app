import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../router.dart';
import 'issue_timer.dart';
import 'timer_notification.dart';
import 'timers_notifier.dart';

/// The device locale's strings, for notifications posted outside any
/// widget tree; falls back to English for unsupported locales.
AppLocalizations _l10n() {
  try {
    return lookupAppLocalizations(PlatformDispatcher.instance.locale);
  } on FlutterError {
    return lookupAppLocalizations(const Locale('en'));
  }
}

final timerNotificationsProvider = Provider<TimerNotifications>((ref) {
  final l10n = _l10n();
  return TimerNotifications(
    pauseLabel: l10n.timerPauseTooltip,
    logLabel: l10n.timeLogButton,
    channelName: l10n.timerNotificationChannelName,
    channelDescription: l10n.timerNotificationChannelDescription,
  );
});

/// Mirrors the timer state into the ongoing notification: shown while a
/// timer runs (also right after a restart that restored one), cleared when
/// nothing runs. Kept alive by the app root, like the share intake.
final timerNotificationSyncProvider = Provider<void>((ref) {
  final notifications = ref.watch(timerNotificationsProvider);
  var permissionAsked = false;
  (int, DateTime?)? shown;

  Future<void> sync(List<IssueTimer> timers) async {
    final running = timers.where((timer) => timer.isRunning).firstOrNull;
    final runningSince = running?.runningSince;
    if (running == null || runningSince == null) {
      shown = null;
      await notifications.clear();
      return;
    }
    // The restore path and the first listener emission overlap; identical
    // content is posted once.
    if (shown == (running.issueId, runningSince)) {
      return;
    }
    shown = (running.issueId, runningSince);
    await notifications.init((action, issueId) {
      switch (action) {
        case TimerNotificationAction.pause:
          ref.read(timersProvider.notifier).pause(issueId);
        case TimerNotificationAction.log:
          router.push('/issues/$issueId?log=1');
        case TimerNotificationAction.open:
          router.push('/issues/$issueId');
      }
    });
    if (!permissionAsked) {
      permissionAsked = true;
      // Asked when the first timer starts, per the lazy-permission rule;
      // the system prompts at most once, and a denial stays silent.
      await notifications.requestPermission();
    }
    // The chronometer anchors to runningSince, so elapsed time shown by
    // the system stays exact across pauses and resumes.
    await notifications.showRunning(
      issueId: running.issueId,
      subject: running.subject,
      runningSince: runningSince.subtract(running.accumulated),
    );
  }

  ref.listen(timersProvider, (previous, next) {
    final timers = next.value;
    if (timers != null) {
      sync(timers);
    }
  });
  // The restore path: a timer that survived a restart gets its reminder
  // back without any state change happening.
  ref.read(timersProvider.future).then(sync).ignore();
});
