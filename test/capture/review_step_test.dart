import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/l10n/generated/app_localizations.dart';
import 'package:georeport/src/features/capture/steps/review_step.dart';
import 'package:latlong2/latlong.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    String subject = 'Cracked pavement',
    String? projectName = 'Field Survey',
    String? trackerName = 'Problem',
    LatLng? location,
    String description = '',
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CaptureReviewStep(
              photos: const [],
              subject: subject,
              projectName: projectName,
              trackerName: trackerName,
              location: location,
              description: description,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('reads back what is about to be sent', (tester) async {
    await pump(tester, description: 'The kerb has lifted');

    expect(find.text('Cracked pavement'), findsOneWidget);
    expect(find.text('Field Survey'), findsOneWidget);
    expect(find.text('Problem'), findsOneWidget);
    expect(find.text('The kerb has lifted'), findsOneWidget);
  });

  testWidgets('says a missing subject is missing', (tester) async {
    // The subject is the one required field, and this is the last screen
    // before submitting, so a blank line here would be the wrong answer.
    await pump(tester, subject: '');

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.captureSubjectRequired), findsOneWidget);
  });

  testWidgets('leaves out an empty description rather than showing a blank', (
    tester,
  ) async {
    await pump(tester);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.captureDescriptionLabel), findsNothing);
  });

  testWidgets('shows coordinates latitude first, as they read on screen', (
    tester,
  ) async {
    // Display order, the opposite of the GeoJSON payload order. Worth
    // pinning: the two conventions sit a few files apart.
    await pump(tester, location: const LatLng(35.681236, 139.767104));

    expect(find.text('35.68124, 139.76710'), findsOneWidget);
  });

  testWidgets('says so when there is no location', (tester) async {
    await pump(tester);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.captureNoLocation), findsOneWidget);
  });
}
