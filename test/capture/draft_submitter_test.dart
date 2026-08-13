import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/capture/issue_draft.dart';
import 'package:georeport/src/capture/queue/draft_store.dart';
import 'package:georeport/src/capture/queue/draft_submitter.dart';
import 'package:georeport/src/capture/queue/queued_draft.dart';

import '../helpers/fake_submit_api.dart';

void main() {
  late Directory root;
  late DraftStore store;
  late FakeSubmitApi api;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('outbox_test');
    store = DraftStore(root);
    api = FakeSubmitApi();
  });

  tearDown(() async {
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  /// A submitter whose image shrinking is a no-op, so the tests are about the
  /// state machine rather than image codecs.
  DraftSubmitter submitter() =>
      DraftSubmitter(api: api, store: store, shrink: (bytes, _) async => bytes);

  Future<QueuedDraft> queue({
    String subject = 'Pothole on Main Street',
    List<DraftPhoto> photos = const [],
    DateTime? createdAt,
  }) {
    return store.add(
      QueuedDraft(
        id: DraftStore.newId(),
        connectionId: 'conn-1',
        createdAt: createdAt ?? DateTime.now().toUtc(),
        projectId: 4,
        trackerId: 2,
        subject: subject,
      ),
      photos,
    );
  }

  DraftPhoto photo(String name) => DraftPhoto(
    filename: name,
    bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF]),
    contentType: 'image/jpeg',
  );

  group('a clean run', () {
    test('uploads each photo, creates the issue, claims the id', () async {
      final draft = await queue(photos: [photo('a.jpg'), photo('b.jpg')]);

      final result = await submitter().process(draft);

      expect(result, isA<SubmitCreated>());
      expect((result as SubmitCreated).issueId, 100);
      expect(api.uploadedFilenames, ['a.jpg', 'b.jpg']);
      expect(api.creates, 1);
      expect(
        await store.claimedIssues(),
        contains(100),
        reason: 'a claimed id must not be adopted by another draft later',
      );
    });

    test('does not re-upload a photo that already has a token', () async {
      // A run interrupted after some uploads must not pay for them twice, on
      // a connection that was poor enough to interrupt it in the first place.
      final draft = await queue(photos: [photo('a.jpg'), photo('b.jpg')]);
      final withOneToken = draft.copyWith(
        photos: [draft.photos.first.withToken('already'), draft.photos.last],
      );
      await store.save(withOneToken);

      await submitter().process(withOneToken);

      expect(api.uploadedFilenames, ['b.jpg']);
    });
  });

  group('exactly-once creation', () {
    test('adopts an issue the interrupted attempt already created', () async {
      // The entry died between "create sent" and "response received". The
      // issue exists; creating a second one would be a duplicate report.
      final draft = await queue();
      final interrupted = draft.copyWith(state: QueuedDraftState.creating);
      await store.save(interrupted);
      api.existing = [(id: 77, subject: 'Pothole on Main Street')];

      final result = await submitter().process(interrupted);

      expect(result, isA<SubmitCreated>());
      expect((result as SubmitCreated).issueId, 77);
      expect(api.creates, 0, reason: 'must not create a duplicate');
      expect(await store.claimedIssues(), contains(77));
    });

    test('ignores an issue this device already claimed', () async {
      // Two drafts with the same subject: the first one\'s issue is spoken
      // for, so the second must create its own rather than adopt it.
      final first = await queue();
      await submitter().process(first);
      expect(await store.claimedIssues(), contains(100));

      final second = await queue();
      final interrupted = second.copyWith(state: QueuedDraftState.creating);
      await store.save(interrupted);
      api
        ..existing = [(id: 100, subject: 'Pothole on Main Street')]
        ..issueId = 101;

      final result = await submitter().process(interrupted);

      expect((result as SubmitCreated).issueId, 101);
      expect(api.creates, 2, reason: 'the claimed id was not available');
    });

    test('creates when the probe finds nothing matching', () async {
      final draft = await queue();
      final interrupted = draft.copyWith(state: QueuedDraftState.creating);
      await store.save(interrupted);
      api.existing = [(id: 55, subject: 'A different issue')];

      final result = await submitter().process(interrupted);

      expect((result as SubmitCreated).issueId, 100);
      expect(api.creates, 1);
    });

    test('retries rather than creating when the probe is refused', () async {
      // The probe uses stock /issues.json, outside the contract, so a narrow
      // OAuth scope or role can refuse it. A refused probe says nothing about
      // whether the issue exists: creating now risks a duplicate.
      final draft = await queue();
      final interrupted = draft.copyWith(state: QueuedDraftState.creating);
      await store.save(interrupted);
      api.lookupError = dioError(status: 403);

      final result = await submitter().process(interrupted);

      expect(result, isA<SubmitRetryLater>());
      expect(api.creates, 0);
      expect(
        (result as SubmitRetryLater).draft.state,
        QueuedDraftState.creating,
        reason: 'still unresolved, so the next round must probe again',
      );
    });
  });

  group('classifying a failure', () {
    test('a connection error goes back to pending, provably unsent', () async {
      final draft = await queue();
      api.createError = dioError(type: DioExceptionType.connectionError);

      final result = await submitter().process(draft);

      expect(result, isA<SubmitRetryLater>());
      final retried = (result as SubmitRetryLater).draft;
      expect(
        retried.state,
        QueuedDraftState.pending,
        reason: 'the request never reached the server, so no dedup is needed',
      );
      expect(retried.attempts, 1);
      expect(retried.nextAttemptAt, isNotNull);
    });

    test('a 500 stays in creating, since the outcome is unknown', () async {
      // The server may have created the issue before failing to answer. The
      // state on disk is what makes the next round probe first.
      final draft = await queue();
      api.createError = dioError(status: 500);

      final result = await submitter().process(draft);

      expect(
        (result as SubmitRetryLater).draft.state,
        QueuedDraftState.creating,
      );
    });

    test('403, 404, 400 and 410 fail rather than retrying forever', () async {
      for (final status in [400, 403, 404, 410]) {
        api = FakeSubmitApi(createError: dioError(status: status));
        final draft = await queue(subject: 'Subject $status');

        final result = await submitter().process(draft);

        expect(
          result,
          isA<SubmitFailed>(),
          reason: 'retrying cannot fix a $status; the user has to act',
        );
        expect((result as SubmitFailed).draft.lastError, 'HTTP $status');
      }
    });

    test('a 422 surfaces the server validation messages', () async {
      final draft = await queue();
      api.createError = dioError(
        status: 422,
        data: {
          'errors': ['Subject cannot be blank', 'Tracker is invalid'],
        },
      );

      final result = await submitter().process(draft);

      expect(
        (result as SubmitFailed).draft.lastError,
        'Subject cannot be blank; Tracker is invalid',
      );
    });
  });

  group('stale upload tokens', () {
    test('a 422 with tokens resets them and retries once', () async {
      // Redmine purges unattached uploads, so a 422 on a payload carrying
      // tokens may just mean they expired. Validation messages are localized,
      // so the condition is detected structurally rather than by text.
      final draft = await queue(photos: [photo('a.jpg')]);
      api.createError = dioError(status: 422);

      final result = await submitter().process(draft);

      expect(result, isA<SubmitRetryLater>());
      final reset = (result as SubmitRetryLater).draft;
      expect(reset.photos.single.token, isNull, reason: 'upload again');
      expect(reset.tokenResets, 1);
      expect(reset.state, QueuedDraftState.pending);
    });

    test('a second 422 is a real rejection', () async {
      final draft = await queue(photos: [photo('a.jpg')]);
      final alreadyReset = draft.copyWith(tokenResets: 1);
      await store.save(alreadyReset);
      api.createError = dioError(status: 422);

      final result = await submitter().process(alreadyReset);

      expect(result, isA<SubmitFailed>());
    });

    test('a 422 with no photos fails immediately', () async {
      final draft = await queue();
      api.createError = dioError(status: 422);

      expect(await submitter().process(draft), isA<SubmitFailed>());
    });
  });

  group('failures that cannot heal', () {
    test('a non-network error fails instead of poisoning the queue', () async {
      // A missing photo file or an undecodable image will never succeed.
      // Leaving it due would stall every entry queued behind it.
      final draft = await queue(photos: [photo('a.jpg')]);
      final missing = DraftSubmitter(
        api: api,
        store: store,
        shrink: (bytes, _) async => throw const FormatException('not an image'),
      );

      final result = await missing.process(draft);

      expect(result, isA<SubmitFailed>());
      expect(
        (result as SubmitFailed).draft.lastError,
        contains('not an image'),
      );
    });
  });

  group('retryDelay', () {
    test('doubles from 30s and caps at 15 minutes on the sixth attempt', () {
      // Written out rather than computed, so a change to the curve has to be
      // stated here rather than following whatever the code now does.
      expect(retryDelay(1), const Duration(seconds: 30));
      expect(retryDelay(2), const Duration(minutes: 1));
      expect(retryDelay(3), const Duration(minutes: 2));
      expect(retryDelay(4), const Duration(minutes: 4));
      expect(retryDelay(5), const Duration(minutes: 8));
      expect(
        retryDelay(6),
        const Duration(minutes: 15),
        reason: 'the sixth would be 16 minutes; the cap takes effect here',
      );
      expect(
        retryDelay(20),
        const Duration(minutes: 15),
        reason: 'a device offline all day must not back off past 15 minutes',
      );
    });

    test('never returns less than the first delay', () {
      // attempts is 1-based; a 0 would otherwise shift the whole curve.
      expect(retryDelay(0), const Duration(seconds: 30));
    });
  });
}
