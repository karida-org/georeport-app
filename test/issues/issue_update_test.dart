import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/features/issues/issue_update.dart';

DioException error({int? status, Object? data}) => DioException(
  requestOptions: RequestOptions(path: '/issues/1.json'),
  type: status == null
      ? DioExceptionType.connectionError
      : DioExceptionType.badResponse,
  response: status == null
      ? null
      : Response(
          requestOptions: RequestOptions(path: '/issues/1.json'),
          statusCode: status,
          data: data,
        ),
);

void main() {
  group('buildIssueUpdatePayload', () {
    test('always pins the lock_version', () {
      final payload = buildIssueUpdatePayload(lockVersion: 7);
      expect(payload['issue'], {'lock_version': 7});
    });

    test('carries status, trimmed note, and uploads when present', () {
      final payload = buildIssueUpdatePayload(
        lockVersion: 7,
        statusId: 2,
        notes: '  Fixed on site  ',
        uploads: [
          {'token': 't', 'filename': 'a.jpg'},
        ],
      );
      final issue = payload['issue'] as Map<String, dynamic>;
      expect(issue['status_id'], 2);
      expect(issue['notes'], 'Fixed on site');
      expect(issue['uploads'], hasLength(1));
    });

    test('a whitespace-only note is omitted entirely', () {
      final payload = buildIssueUpdatePayload(lockVersion: 7, notes: '   ');
      expect(
        (payload['issue'] as Map<String, dynamic>).containsKey('notes'),
        isFalse,
      );
    });
  });

  group('isStaleWriteError', () {
    test('409 is a conflict', () {
      expect(isStaleWriteError(error(status: 409)), isTrue);
    });

    test('RedMica 422 with an empty errors list is a conflict', () {
      expect(
        isStaleWriteError(error(status: 422, data: {'errors': <Object>[]})),
        isTrue,
      );
      expect(
        isStaleWriteError(error(status: 422, data: <String, Object>{})),
        isTrue,
      );
    });

    test('a 422 with real validation messages is not a conflict', () {
      expect(
        isStaleWriteError(
          error(
            status: 422,
            data: {
              'errors': ['Status is invalid'],
            },
          ),
        ),
        isFalse,
      );
    });

    test('network failures are not conflicts', () {
      expect(isStaleWriteError(error()), isFalse);
    });
  });

  test('field edits merge in, with versioning keys winning', () {
    final payload = buildIssueUpdatePayload(
      lockVersion: 7,
      fields: {
        'subject': 'New subject',
        'assigned_to_id': '',
        'due_date': '2026-08-20',
        'lock_version': 999, // must not override the loaded version
      },
    );
    final issue = payload['issue'] as Map<String, dynamic>;
    expect(issue['subject'], 'New subject');
    expect(issue['assigned_to_id'], '');
    expect(issue['due_date'], '2026-08-20');
    expect(issue['lock_version'], 7);
    expect(issue.containsKey('status_id'), isFalse);
  });

  test('reserved keys cannot be smuggled in through fields', () {
    final payload = buildIssueUpdatePayload(
      lockVersion: 3,
      fields: {
        'subject': 'Kept',
        // All four are owned by the function's own parameters.
        'lock_version': 999,
        'status_id': 42,
        'notes': 'sneaky',
        'uploads': [
          {'token': 'x'},
        ],
      },
    );
    final issue = payload['issue'] as Map<String, dynamic>;
    expect(issue['subject'], 'Kept');
    expect(issue['lock_version'], 3);
    expect(issue.containsKey('status_id'), isFalse);
    expect(issue.containsKey('notes'), isFalse);
    expect(issue.containsKey('uploads'), isFalse);
  });
}
