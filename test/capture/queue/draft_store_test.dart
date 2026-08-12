import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/capture/issue_draft.dart';
import 'package:georeport/src/capture/queue/draft_store.dart';
import 'package:georeport/src/capture/queue/queued_draft.dart';

QueuedDraft entry(String id) => QueuedDraft(
  id: id,
  connectionId: 'conn-1',
  createdAt: DateTime.utc(2026, 8, 12),
  projectId: 1,
  trackerId: 4,
  subject: 'Subject $id',
);

void main() {
  late Directory root;
  late DraftStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('outbox_test');
    store = DraftStore(root);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('add persists photos as files and lists the entry back', () async {
    final photoBytes = Uint8List.fromList([1, 2, 3, 4]);
    final queued = await store.add(entry('a'), [
      DraftPhoto(
        filename: 'IMG_1.jpg',
        bytes: photoBytes,
        contentType: 'image/jpeg',
      ),
    ]);

    expect(queued.photos, hasLength(1));
    expect(await store.readPhoto(queued, queued.photos.single), photoBytes);

    final listed = await store.list();
    expect(listed, hasLength(1));
    expect(listed.single.subject, 'Subject a');
    expect(listed.single.photos.single.filename, 'IMG_1.jpg');
  });

  test('list returns oldest first and skips corrupt entries', () async {
    await store.save(entry('new').copyWith());
    await store.save(
      QueuedDraft(
        id: 'old',
        connectionId: 'conn-1',
        createdAt: DateTime.utc(2020),
        projectId: 1,
        trackerId: 4,
        subject: 'Oldest',
      ),
    );
    File('${root.path}/broken.json').writeAsStringSync('not json');

    final listed = await store.list();
    expect(listed, hasLength(2));
    expect(listed.first.id, 'old');
  });

  test('remove deletes the record and its photo directory', () async {
    final queued = await store.add(entry('gone'), [
      DraftPhoto(filename: 'x.jpg', bytes: Uint8List.fromList([9])),
    ]);
    await store.remove(queued.id);

    expect(await store.list(), isEmpty);
    expect(Directory('${root.path}/gone').existsSync(), isFalse);
  });
}
