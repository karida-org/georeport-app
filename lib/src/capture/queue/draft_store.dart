import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../issue_draft.dart';
import 'queued_draft.dart';

/// Filesystem persistence for the outbox: one `<id>.json` per queued draft
/// next to a `<id>/` directory holding its photo files. Everything survives
/// app restarts; nothing is kept only in memory.
class DraftStore {
  DraftStore(this._root);

  final Directory _root;

  static final _random = Random.secure();

  static String newId() {
    final suffix = List.generate(
      8,
      (_) => _random.nextInt(16).toRadixString(16),
    ).join();
    return '${DateTime.now().toUtc().millisecondsSinceEpoch}-$suffix';
  }

  File _jsonFile(String id) => File('${_root.path}/$id.json');
  Directory _photoDir(String id) => Directory('${_root.path}/$id');

  /// All queued drafts, oldest first. Unreadable entries are skipped rather
  /// than blocking the rest of the queue.
  Future<List<QueuedDraft>> list() async {
    if (!_root.existsSync()) {
      return const [];
    }
    final drafts = <QueuedDraft>[];
    await for (final entity in _root.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is Map<String, dynamic>) {
          drafts.add(QueuedDraft.fromJson(decoded));
        }
      } on Exception {
        continue;
      }
    }
    drafts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return drafts;
  }

  /// Persists a new entry: photo bytes become files first, then the JSON
  /// record appears, so a crash in between leaves stray files but never a
  /// record pointing at missing photos.
  Future<QueuedDraft> add(QueuedDraft draft, List<DraftPhoto> photos) async {
    final photoDir = _photoDir(draft.id)..createSync(recursive: true);
    final queuedPhotos = <QueuedPhoto>[];
    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      final storedName = 'photo_$i';
      await File(
        '${photoDir.path}/$storedName',
      ).writeAsBytes(photo.bytes, flush: true);
      queuedPhotos.add(
        QueuedPhoto(
          storedName: storedName,
          filename: photo.filename,
          contentType: photo.contentType,
        ),
      );
    }
    final queued = draft.copyWith(photos: queuedPhotos);
    await save(queued);
    return queued;
  }

  /// Atomic: written to a sidecar and renamed into place, so a kill during
  /// the write can never truncate a record (and its upload tokens) away.
  /// The `.tmp` suffix keeps half-written files out of [list]'s json filter.
  Future<void> save(QueuedDraft draft) async {
    _root.createSync(recursive: true);
    final target = _jsonFile(draft.id);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(jsonEncode(draft.toJson()), flush: true);
    await temp.rename(target.path);
  }

  Future<Uint8List> readPhoto(QueuedDraft draft, QueuedPhoto photo) =>
      File('${_photoDir(draft.id).path}/${photo.storedName}').readAsBytes();

  /// Cheap existence check (one stat), used by the queue to honor a
  /// discard that happened after its pass snapshot was taken.
  bool exists(String id) => _jsonFile(id).existsSync();

  Future<void> remove(String id) async {
    final json = _jsonFile(id);
    if (json.existsSync()) {
      await json.delete();
    }
    final photos = _photoDir(id);
    if (photos.existsSync()) {
      await photos.delete(recursive: true);
    }
  }

  /// Reclaims photo directories left behind by an interrupted [add] or
  /// [remove]; photos are large, so orphans must not accumulate.
  Future<void> sweepOrphans() async {
    if (!_root.existsSync()) {
      return;
    }
    await for (final entity in _root.list()) {
      if (entity is Directory &&
          !_jsonFile(
            entity.path.split(Platform.pathSeparator).last,
          ).existsSync()) {
        await entity.delete(recursive: true);
      }
    }
  }

  File get _claimedFile => File('${_root.path}/claimed_issues.ledger');

  /// Issue ids this device already created or adopted. The dedup check for
  /// an interrupted create must never adopt one of these, otherwise two
  /// same-subject drafts could both resolve to the same issue and one
  /// report would silently vanish.
  Future<List<int>> claimedIssues() async {
    try {
      if (!_claimedFile.existsSync()) {
        return const [];
      }
      final decoded = jsonDecode(await _claimedFile.readAsString());
      return decoded is List
          ? decoded.whereType<num>().map((id) => id.toInt()).toList()
          : const [];
    } on Exception {
      return const [];
    }
  }

  Future<void> claimIssue(int issueId) async {
    _root.createSync(recursive: true);
    final claimed = await claimedIssues();
    if (claimed.contains(issueId)) {
      return;
    }
    // Only recent ids matter (the dedup window is minutes); keep it bounded.
    final updated = [...claimed, issueId].reversed.take(200).toList().reversed;
    final temp = File('${_claimedFile.path}.tmp');
    await temp.writeAsString(jsonEncode(updated.toList()), flush: true);
    await temp.rename(_claimedFile.path);
  }
}
