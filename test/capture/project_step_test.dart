import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/l10n/generated/app_localizations.dart';
import 'package:georeport/src/api/models/bundle.dart';
import 'package:georeport/src/api/models/project_schema.dart';
import 'package:georeport/src/features/capture/steps/project_step.dart';

BundleProject _project(int id, String name) =>
    BundleProject(id: id, identifier: 'p$id', name: name, hasBoundary: false);

ProjectSchema _schema(List<SchemaTracker> trackers) => ProjectSchema(
  trackers: trackers,
  customFields: const [],
  writable: const {},
);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    List<SchemaTracker> trackers = const [
      SchemaTracker(id: 2, name: 'Problem'),
    ],
    int? trackerId = 2,
    bool enabled = true,
    ValueChanged<int?>? onTrackerChanged,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CaptureProjectStep(
            projects: [_project(4, 'Field Survey'), _project(5, 'Roads')],
            projectId: 4,
            schema: _schema(trackers),
            trackerId: trackerId,
            enabled: enabled,
            onProjectChanged: (_) {},
            onTrackerChanged: onTrackerChanged ?? (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('shows the current project and tracker', (tester) async {
    await pump(tester);

    expect(find.text('Field Survey'), findsOneWidget);
    expect(find.text('Problem'), findsOneWidget);
  });

  testWidgets('says so when the project has no trackers', (tester) async {
    // A project with no tracker cannot receive an issue at all, so the
    // dropdown is replaced by an explanation rather than left empty.
    await pump(tester, trackers: const [], trackerId: null);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.captureNoTrackers), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
  });

  testWidgets('cannot be re-aimed while a submission is in flight', (
    tester,
  ) async {
    await pump(tester, enabled: false);

    final dropdowns = tester.widgetList<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    expect(dropdowns, hasLength(2));
    expect(dropdowns.every((d) => d.onChanged == null), isTrue);
  });
}
