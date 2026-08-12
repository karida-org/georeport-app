import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/app.dart';
import 'package:georeport/src/connections/connection_manager.dart';

import 'helpers/in_memory_secret_store.dart';

Widget _app(Locale locale) {
  return ProviderScope(
    overrides: [secretStoreProvider.overrideWithValue(InMemorySecretStore())],
    child: GeoreportApp(locale: locale),
  );
}

void main() {
  testWidgets('boots to the connect screen in English', (tester) async {
    await tester.pumpWidget(_app(const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Georeport'), findsOneWidget);
    expect(
      find.text('Capture and work on GTT-Redmine issues in the field.'),
      findsOneWidget,
    );
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('boots to the connect screen in Japanese', (tester) async {
    await tester.pumpWidget(_app(const Locale('ja')));
    await tester.pumpAndSettle();

    expect(find.text('Georeport'), findsOneWidget);
    expect(find.text('GTT-Redmine のチケットを現場から登録・処理できるアプリです。'), findsOneWidget);
    expect(find.text('次へ'), findsOneWidget);
  });
}
