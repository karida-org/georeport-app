import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'router.dart';

class GeoreportApp extends StatelessWidget {
  const GeoreportApp({super.key, this.locale});

  /// Forces a locale instead of following the device setting. Used in tests.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      routerConfig: router,
    );
  }
}
