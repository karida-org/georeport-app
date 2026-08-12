import 'dart:convert';
import 'dart:io';

import 'issue_timer.dart';

/// Disk persistence for the timers: one JSON file, written atomically
/// (sidecar + rename), so a timer started in the morning survives app kills
/// and phone reboots. Same discipline as the outbox.
class TimerStore {
  TimerStore(this._file);

  final File _file;

  Future<List<IssueTimer>> load() async {
    try {
      if (!await _file.exists()) {
        return const [];
      }
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! List) {
        return const [];
      }
      return [
        for (final entry in decoded)
          if (entry is Map<String, dynamic>) IssueTimer.fromJson(entry),
      ];
    } on Exception {
      return const [];
    }
  }

  Future<void> save(List<IssueTimer> timers) async {
    _file.parent.createSync(recursive: true);
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(
      jsonEncode([for (final timer in timers) timer.toJson()]),
      flush: true,
    );
    await temp.rename(_file.path);
  }
}
