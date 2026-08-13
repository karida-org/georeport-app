import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/models/issue_document.dart';
import 'package:georeport/src/features/time/quick_log_gate.dart';

/// The real document shape, with the one permission under test set per case.
IssueDocument _document({required bool canLogTime}) {
  final json =
      jsonDecode(File('test/fixtures/issue_document.json').readAsStringSync())
          as Map<String, dynamic>;
  (json['editable'] as Map<String, dynamic>)['can_log_time'] = canLogTime;
  return IssueDocument.fromJson(json);
}

void main() {
  group('canOpenQuickLog', () {
    test('opens when the server and the issue both allow it', () {
      expect(
        canOpenQuickLog(
          alreadyOpened: false,
          serverAllowsCreate: true,
          document: _document(canLogTime: true),
        ),
        isTrue,
      );
    });

    test('stays shut when this user may not log time on this issue', () {
      // Opening anyway would put the user in front of a form the server
      // answers with 403.
      expect(
        canOpenQuickLog(
          alreadyOpened: false,
          serverAllowsCreate: true,
          document: _document(canLogTime: false),
        ),
        isFalse,
      );
    });

    test('stays shut when the server has no time-entry contract', () {
      // An older plugin version. The issue-level permission says yes, but
      // there is no endpoint to post to.
      expect(
        canOpenQuickLog(
          alreadyOpened: false,
          serverAllowsCreate: false,
          document: _document(canLogTime: true),
        ),
        isFalse,
      );
    });

    test('opens once, not again when the document arrives a second time', () {
      // A refresh, or a retry after an error, re-delivers the document. The
      // user should not get a second sheet on top of the first.
      expect(
        canOpenQuickLog(
          alreadyOpened: true,
          serverAllowsCreate: true,
          document: _document(canLogTime: true),
        ),
        isFalse,
      );
    });
  });
}
