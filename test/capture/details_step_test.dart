import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/l10n/generated/app_localizations.dart';
import 'package:georeport/src/api/models/project_schema.dart';
import 'package:georeport/src/features/capture/steps/details_step.dart';

SchemaCustomField _field({
  required int id,
  required String name,
  bool required = false,
}) {
  return SchemaCustomField(
    id: id,
    name: name,
    fieldFormat: 'string',
    required: required,
    multiple: false,
    possibleValues: const [],
    trackerIds: const [],
  );
}

void main() {
  late TextEditingController subject;
  late TextEditingController description;

  setUp(() {
    subject = TextEditingController();
    description = TextEditingController();
  });

  tearDown(() {
    subject.dispose();
    description.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    required List<SchemaCustomField> fields,
    bool showOptional = false,
    Map<int, Object> values = const {},
    void Function(int, Object?)? onFieldChanged,
    VoidCallback? onToggleOptional,
    bool enabled = true,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CaptureDetailsStep(
              subjectController: subject,
              descriptionController: description,
              fields: fields,
              values: values,
              enabled: enabled,
              showOptional: showOptional,
              onToggleOptional: onToggleOptional ?? () {},
              onFieldChanged: onFieldChanged ?? (_, _) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows required fields, marked with an asterisk', (tester) async {
    await pump(
      tester,
      fields: [_field(id: 1, name: 'Severity', required: true)],
    );

    expect(
      find.text('Severity *'),
      findsOneWidget,
      reason: 'the asterisk is the only thing marking a field as required',
    );
  });

  testWidgets('hides optional fields behind the toggle', (tester) async {
    // A tracker with many optional fields would otherwise bury the subject
    // line under things nobody has to answer.
    await pump(tester, fields: [_field(id: 2, name: 'Reported via')]);

    expect(find.text('Reported via'), findsNothing);

    await pump(
      tester,
      fields: [_field(id: 2, name: 'Reported via')],
      showOptional: true,
    );

    expect(find.text('Reported via'), findsOneWidget);
  });

  testWidgets('offers no toggle when everything is required', (tester) async {
    await pump(
      tester,
      fields: [_field(id: 1, name: 'Severity', required: true)],
    );

    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('reports a cleared field as null, not as empty', (tester) async {
    // Null is how "not answered" is expressed; an empty string would count
    // as an answer and satisfy a required field.
    final changes = <(int, Object?)>[];
    await pump(
      tester,
      fields: [_field(id: 1, name: 'Severity', required: true)],
      values: const {1: 'High'},
      onFieldChanged: (id, value) => changes.add((id, value)),
    );

    await tester.enterText(find.byType(TextField).last, '');
    await tester.pump();

    expect(changes.last, (1, null));
  });

  testWidgets('locks the text inputs while a submission is in flight', (
    tester,
  ) async {
    // Only the subject and description today. The custom field editors and
    // the optional-fields toggle stay live, which is issue #91; this test
    // claims exactly what holds rather than what should.
    await pump(tester, fields: const [], enabled: false);

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields, hasLength(2));
    expect(fields.every((field) => field.enabled == false), isTrue);
  });
}
