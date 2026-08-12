import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import 'router.dart';
import 'share/share_intake.dart';
import 'theme.dart';
import 'time/timer_notification_sync.dart';

class GeoreportApp extends ConsumerWidget {
  const GeoreportApp({super.key, this.locale});

  /// Forces a locale instead of following the device setting. Used in tests.
  final Locale? locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the share intake alive for the whole app (images shared from
    // other apps open the capture flow whenever a session is ready) without
    // rebuilding the MaterialApp on its state changes.
    ref.listen(shareIntakeProvider, (previous, next) {});
    // Mirrors running timers into the ongoing notification for the whole
    // app lifetime; a void provider, so this never rebuilds anything.
    ref.watch(timerNotificationSyncProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: georeportLightTheme,
      darkTheme: georeportDarkTheme,
      routerConfig: router,
    );
  }
}
