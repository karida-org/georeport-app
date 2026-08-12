import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';

void main() {
  // The bundled IBM Plex fonts are not a pub package, so their OFL license
  // must be registered by hand to appear on the licenses page.
  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString('fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const [
      'IBM Plex Sans',
      'IBM Plex Sans JP',
    ], ofl);
  });
  runApp(const ProviderScope(child: GeoreportApp()));
}
