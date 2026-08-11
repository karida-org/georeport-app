import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/app.dart';

void main() {
  testWidgets('boots to the home screen in English', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: GeoreportApp(locale: Locale('en'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Georeport'), findsOneWidget);
    expect(
      find.text('Capture and work on GTT-Redmine issues in the field.'),
      findsOneWidget,
    );
  });

  testWidgets('boots to the home screen in Japanese', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: GeoreportApp(locale: Locale('ja'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Georeport'), findsOneWidget);
    expect(find.text('GTT-Redmine のチケットを現場から登録・処理できるアプリです。'), findsOneWidget);
  });
}
