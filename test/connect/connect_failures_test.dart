import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/l10n/generated/app_localizations.dart';
import 'package:georeport/src/auth/oauth_flow.dart';
import 'package:georeport/src/connections/connection_manager.dart';
import 'package:georeport/src/features/connect/connect_screen.dart';

import '../helpers/in_memory_secret_store.dart';

/// The connect screen on its own, with no server and no stored connections.
///
/// Only the paths that stop *before* any request are exercised here: letting
/// the screen probe would make a real network call from a unit test. That the
/// validation accepts real addresses is covered in `test/api/base_url_test`,
/// against a longer list of inputs than a widget test could carry.
Future<void> pumpConnectScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [secretStoreProvider.overrideWithValue(InMemorySecretStore())],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConnectScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> enterAddress(WidgetTester tester, String address) async {
  await tester.enterText(find.byType(TextField).first, address);
  // The Continue button is disabled while the field is empty, so the state
  // has to settle before it can be tapped.
  await tester.pump();
}

void main() {
  testWidgets('a malformed address is refused in plain language', (
    tester,
  ) async {
    // The reported input. Before this, it reached Uri.parse and the screen
    // showed "FormatException: Illegal scheme character (at character 5)"
    // with a caret diagram underneath.
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await pumpConnectScreen(tester);

    await enterAddress(tester, 'http 10.0.2.2 3000http://10.0.2.2:3000');
    await tester.tap(find.text(l10n.connectContinueButton));
    await tester.pump();

    expect(find.text(l10n.connectInvalidUrl), findsOneWidget);
    expect(
      find.textContaining('FormatException'),
      findsNothing,
      reason: 'the parser diagnostic must never reach the screen',
    );
  });

  testWidgets('a refused address leaves the screen usable', (tester) async {
    // Rejecting before the request means the busy flag is never set, so the
    // user can correct the typo and try again straight away rather than
    // watching a spinner that will not finish.
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await pumpConnectScreen(tester);

    await enterAddress(tester, 'not an address');
    await tester.tap(find.text(l10n.connectContinueButton));
    await tester.pump();

    expect(find.text(l10n.connectInvalidUrl), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton).first);
    expect(button.onPressed, isNotNull);
  });

  test('the refusal shows the shape of a right answer', () async {
    // A message that only says "no" leaves the user guessing at the step
    // where they are least oriented.
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));

    expect(en.connectInvalidUrl, contains('https://'));
    expect(ja.connectInvalidUrl, contains('https://'));
  });

  test('the timeout message says what to do next', () async {
    // A bare "timed out" tells the user nothing they can act on.
    final en = await AppLocalizations.delegate.load(const Locale('en'));

    expect(en.connectTimedOut, contains('try again'));
  });

  group('the step bounds', () {
    test('never cut off a browser sign-in that is going fine', () {
      // The regression this guards: a single 90s bound covering every step
      // also covered the OAuth path, where the user is still typing their
      // password in the browser. The outer backstop has to sit above the
      // inner bound, or sign-in dies mid-flow with the wrong message.
      expect(
        ConnectScreen.oauthConnectTimeout,
        greaterThan(OAuthFlow.browserTimeout),
      );
    });

    test('allow the whole api-key sequence its per-request budget', () {
      // Five requests at up to 30s of receive time each. A bound below that
      // sum fails slow-but-working instances, which is worse than waiting.
      expect(
        ConnectScreen.apiKeyConnectTimeout,
        greaterThanOrEqualTo(const Duration(seconds: 150)),
      );
    });

    test('bound the single-request probe more tightly than a full connect', () {
      expect(
        ConnectScreen.probeTimeout,
        lessThan(ConnectScreen.apiKeyConnectTimeout),
      );
    });
  });
}
