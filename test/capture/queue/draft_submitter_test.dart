import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/issue_submit_api.dart';
import 'package:georeport/src/capture/issue_draft.dart';
import 'package:georeport/src/capture/queue/draft_store.dart';
import 'package:georeport/src/capture/queue/draft_submitter.dart';
import 'package:georeport/src/capture/queue/queued_draft.dart';

/// Scriptable fake: each function can be swapped per test, and calls are
/// recorded so the tests can assert what did (not) reach the server.
class FakeApi implements IssueSubmitApi {
  int uploads = 0;
  int creates = 0;
  int dedupChecks = 0;
  Future<String> Function()? onUpload;
  Future<int> Function()? onCreate;
  List<CreatedIssue> existing = const [];

  @override
  Future<String> uploadFile(List<int> bytes, String filename) {
    uploads++;
    return onUpload?.call() ?? Future.value('tok-$uploads');
  }

  @override
  Future<int> createIssue(Map<String, dynamic> payload) {
    creates++;
    return onCreate?.call() ?? Future.value(99);
  }

  @override
  Future<List<CreatedIssue>> myIssuesCreatedSince({
    required int projectId,
    required DateTime since,
  }) {
    dedupChecks++;
    return Future.value(existing);
  }
}

DioException dioError(DioExceptionType type, {int? status, Object? data}) =>
    DioException(
      requestOptions: RequestOptions(path: '/issues.json'),
      type: type,
      response: status == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: '/issues.json'),
              statusCode: status,
              data: data,
            ),
    );

void main() {
  late Directory root;
  late DraftStore store;
  late FakeApi api;
  late DraftSubmitter submitter;

  setUp(() {
    root = Directory.systemTemp.createTempSync('submitter_test');
    store = DraftStore(root);
    api = FakeApi();
    submitter = DraftSubmitter(
      api: api,
      store: store,
      shrink: (bytes, contentType) async => bytes,
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<QueuedDraft> queued({int photos = 2}) => store.add(
    QueuedDraft(
      id: DraftStore.newId(),
      connectionId: 'conn-1',
      createdAt: DateTime.now().toUtc(),
      projectId: 1,
      trackerId: 4,
      subject: 'Pothole at the gate',
    ),
    [
      for (var i = 0; i < photos; i++)
        DraftPhoto(
          filename: 'IMG_$i.jpg',
          bytes: Uint8List.fromList([i]),
          contentType: 'image/jpeg',
        ),
    ],
  );

  test(
    'happy path uploads every photo, creates once, reports the id',
    () async {
      final result = await submitter.process(await queued());

      expect(result, isA<SubmitCreated>());
      expect((result as SubmitCreated).issueId, 99);
      expect(api.uploads, 2);
      expect(api.creates, 1);
      expect(api.dedupChecks, 0);
    },
  );

  test(
    'a failed upload keeps earlier tokens and resumes where it stopped',
    () async {
      var uploadCalls = 0;
      api.onUpload = () {
        uploadCalls++;
        if (uploadCalls == 2) {
          throw dioError(DioExceptionType.connectionError);
        }
        return Future.value('tok-$uploadCalls');
      };

      final result = await submitter.process(await queued());
      expect(result, isA<SubmitRetryLater>());
      expect(api.creates, 0);

      final persisted = (await store.list()).single;
      expect(persisted.photos.first.token, 'tok-1');
      expect(persisted.photos.last.token, isNull);
      expect(persisted.state, QueuedDraftState.pending);
      expect(persisted.attempts, 1);
      expect(persisted.nextAttemptAt, isNotNull);

      // Next round only the missing photo goes up.
      api.onUpload = null;
      final retry = await submitter.process(persisted);
      expect(retry, isA<SubmitCreated>());
      expect(uploadCalls, 2);
      expect(api.uploads, 3);
      expect(api.creates, 1);
    },
  );

  test('a create that provably never reached the server retries without '
      'a dedup check', () async {
    api.onCreate = () => throw dioError(DioExceptionType.connectionError);

    final result = await submitter.process(await queued(photos: 0));
    expect(result, isA<SubmitRetryLater>());

    final persisted = (await store.list()).single;
    expect(persisted.state, QueuedDraftState.pending);

    api.onCreate = null;
    final retry = await submitter.process(persisted);
    expect(retry, isA<SubmitCreated>());
    expect(api.dedupChecks, 0);
    expect(api.creates, 2);
  });

  test('a create with an unknown outcome asks the server before retrying, '
      'and adopts the issue it finds', () async {
    api.onCreate = () => throw dioError(DioExceptionType.receiveTimeout);

    final result = await submitter.process(await queued(photos: 0));
    expect(result, isA<SubmitRetryLater>());

    final persisted = (await store.list()).single;
    expect(persisted.state, QueuedDraftState.creating);

    // The interrupted create actually went through on the server.
    api.existing = const [(id: 4242, subject: 'Pothole at the gate')];
    final retry = await submitter.process(persisted);

    expect(retry, isA<SubmitCreated>());
    expect((retry as SubmitCreated).issueId, 4242);
    expect(api.dedupChecks, 1);
    expect(api.creates, 1, reason: 'the create must never run twice');
  });

  test(
    'an unknown outcome that turns out uncreated is created normally',
    () async {
      api.onCreate = () => throw dioError(DioExceptionType.receiveTimeout);
      await submitter.process(await queued(photos: 0));

      api.onCreate = null;
      api.existing = const [(id: 1, subject: 'Something else entirely')];
      final retry = await submitter.process((await store.list()).single);

      expect(retry, isA<SubmitCreated>());
      expect((retry as SubmitCreated).issueId, 99);
      expect(api.dedupChecks, 1);
      expect(api.creates, 2);
    },
  );

  test(
    'a validation rejection is permanent and keeps the server message',
    () async {
      api.onCreate = () => throw dioError(
        DioExceptionType.badResponse,
        status: 422,
        data: {
          'errors': ['Subject cannot be blank'],
        },
      );

      final result = await submitter.process(await queued(photos: 0));
      expect(result, isA<SubmitFailed>());

      final persisted = (await store.list()).single;
      expect(persisted.state, QueuedDraftState.failed);
      expect(persisted.lastError, contains('Subject cannot be blank'));
    },
  );

  test(
    'a stale attachment token clears the tokens for a fresh upload',
    () async {
      api.onCreate = () => throw dioError(
        DioExceptionType.badResponse,
        status: 422,
        data: {
          'errors': ['Attachment is invalid'],
        },
      );

      final result = await submitter.process(await queued());
      expect(result, isA<SubmitRetryLater>());

      final persisted = (await store.list()).single;
      expect(persisted.state, QueuedDraftState.pending);
      expect(persisted.photos.every((photo) => photo.token == null), isTrue);
    },
  );
}
