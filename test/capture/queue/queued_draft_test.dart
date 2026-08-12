import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/capture/queue/queued_draft.dart';
import 'package:latlong2/latlong.dart';

QueuedDraft sampleDraft() => QueuedDraft(
  id: 'abc-123',
  connectionId: 'conn-1',
  createdAt: DateTime.utc(2026, 8, 12, 5, 0),
  projectId: 1,
  trackerId: 4,
  subject: 'Broken light',
  description: 'Near the gate',
  location: const LatLng(34.6864, 135.1959),
  customFieldValues: const {
    3: '1',
    5: ['Web', 'Phone'],
  },
  photos: const [
    QueuedPhoto(
      storedName: 'photo_0',
      filename: 'IMG_1.jpg',
      contentType: 'image/jpeg',
      token: 'tok-1',
    ),
    QueuedPhoto(storedName: 'photo_1', filename: 'IMG_2.jpg'),
  ],
  state: QueuedDraftState.creating,
  attempts: 2,
  tokenResets: 1,
  nextAttemptAt: DateTime.utc(2026, 8, 12, 5, 5),
  lastError: 'timeout',
);

void main() {
  test('survives a JSON roundtrip', () {
    final draft = sampleDraft();
    final revived = QueuedDraft.fromJson(
      jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>,
    );

    expect(revived.id, draft.id);
    expect(revived.connectionId, draft.connectionId);
    expect(revived.createdAt, draft.createdAt);
    expect(revived.subject, draft.subject);
    expect(revived.location, draft.location);
    expect(revived.customFieldValues[3], '1');
    expect(revived.customFieldValues[5], ['Web', 'Phone']);
    expect(revived.photos, hasLength(2));
    expect(revived.photos.first.token, 'tok-1');
    expect(revived.photos.last.token, isNull);
    expect(revived.state, QueuedDraftState.creating);
    expect(revived.attempts, 2);
    expect(revived.tokenResets, 1);
    expect(revived.nextAttemptAt, draft.nextAttemptAt);
    expect(revived.lastError, 'timeout');
  });

  test('payload carries only uploaded photos and the geojson feature', () {
    final payload = sampleDraft().payload();
    final issue = payload['issue'] as Map<String, dynamic>;

    expect(issue['subject'], 'Broken light');
    expect(issue['geojson'], contains('135.1959'));
    final uploads = issue['uploads'] as List;
    expect(uploads, hasLength(1));
    expect((uploads.single as Map)['token'], 'tok-1');
  });

  test('withToken(null) clears an uploaded photo back to pending', () {
    final photo = sampleDraft().photos.first.withToken(null);
    expect(photo.token, isNull);
    expect(photo.filename, 'IMG_1.jpg');
  });
}
