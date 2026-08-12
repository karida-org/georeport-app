import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'issue_timer.dart';
import 'timer_store.dart';

final timerStoreProvider = FutureProvider<TimerStore>((ref) async {
  final documents = await getApplicationDocumentsDirectory();
  return TimerStore(File('${documents.path}/timers.json'));
});

/// The wall clock, as a seam so tests can freeze it.
final clockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

final timersProvider = AsyncNotifierProvider<TimersNotifier, List<IssueTimer>>(
  TimersNotifier.new,
);

/// Owns the per-issue timers under the agreed model: any number of PAUSED
/// timers, at most one RUNNING. Starting (or resuming) a timer pauses the
/// running one, so total tracked time can never exceed wall clock; genuinely
/// parallel work stays a deliberate later feature, not a silent default.
/// Every mutation is persisted before it is reported.
class TimersNotifier extends AsyncNotifier<List<IssueTimer>> {
  TimerStore? _store;

  @override
  Future<List<IssueTimer>> build() async {
    final store = await ref.watch(timerStoreProvider.future);
    _store = store;
    return store.load();
  }

  DateTime get _now => ref.read(clockProvider)();

  List<IssueTimer> get _timers => state.value ?? const [];

  IssueTimer? get running =>
      _timers.where((timer) => timer.isRunning).firstOrNull;

  IssueTimer? timerFor(int issueId) =>
      _timers.where((timer) => timer.issueId == issueId).firstOrNull;

  /// Starts (or resumes) the timer for an issue. Returns the issue id of the
  /// timer that was auto-paused to keep the one-running rule, so the UI can
  /// offer undo; null when nothing was running.
  Future<int?> start({
    required int issueId,
    required int projectId,
    required String subject,
  }) async {
    final now = _now;
    final previous = running;
    if (previous?.issueId == issueId) {
      return null; // already running
    }
    var timers = _pauseAll(now);
    final existing = timers.where((t) => t.issueId == issueId).firstOrNull;
    if (existing != null) {
      timers = [
        for (final timer in timers)
          if (timer.issueId == issueId)
            timer.copyWith(runningSince: now)
          else
            timer,
      ];
    } else {
      timers = [
        ...timers,
        IssueTimer(
          issueId: issueId,
          projectId: projectId,
          subject: subject,
          startedAt: now,
          runningSince: now,
        ),
      ];
    }
    await _commit(timers);
    return previous?.issueId;
  }

  Future<void> pause(int issueId) async {
    final now = _now;
    await _commit([
      for (final timer in _timers)
        if (timer.issueId == issueId && timer.isRunning)
          timer.copyWith(accumulated: timer.elapsed(now), clearRunning: true)
        else
          timer,
    ]);
  }

  /// Removes the timer and returns its total tracked time, for the quick
  /// log prefill. Null when no timer exists for the issue.
  Future<Duration?> stop(int issueId) async {
    final timer = timerFor(issueId);
    if (timer == null) {
      return null;
    }
    final elapsed = timer.elapsed(_now);
    await _commit([
      for (final t in _timers)
        if (t.issueId != issueId) t,
    ]);
    return elapsed;
  }

  List<IssueTimer> _pauseAll(DateTime now) => [
    for (final timer in _timers)
      if (timer.isRunning)
        timer.copyWith(accumulated: timer.elapsed(now), clearRunning: true)
      else
        timer,
  ];

  Future<void> _commit(List<IssueTimer> timers) async {
    // Resolve the store on demand: a mutation racing build() must still
    // persist, or the survives-app-kill invariant silently breaks.
    final TimerStore store =
        _store ?? await ref.read(timerStoreProvider.future);
    _store = store;
    await store.save(timers);
    state = AsyncData(timers);
  }
}
