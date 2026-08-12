import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/time/issue_timer.dart';
import 'package:georeport/src/time/timer_store.dart';
import 'package:georeport/src/time/timers_notifier.dart';

void main() {
  late Directory root;
  late TimerStore store;
  late DateTime now;
  late ProviderContainer container;

  setUp(() {
    root = Directory.systemTemp.createTempSync('timers_test');
    store = TimerStore(File('${root.path}/timers.json'));
    now = DateTime.utc(2026, 8, 12, 9);
    container = ProviderContainer(
      overrides: [
        timerStoreProvider.overrideWith((ref) async => store),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<TimersNotifier> notifier() async {
    await container.read(timersProvider.future);
    return container.read(timersProvider.notifier);
  }

  test('starting a second timer pauses the first: one running, ever', () async {
    final timers = await notifier();
    await timers.start(issueId: 1, projectId: 4, subject: 'Fence');
    now = now.add(const Duration(minutes: 30));

    final paused = await timers.start(
      issueId: 2,
      projectId: 4,
      subject: 'Pipe',
    );

    expect(paused, 1, reason: 'the UI needs the paused id for undo');
    final state = container.read(timersProvider).value!;
    final fence = state.singleWhere((t) => t.issueId == 1);
    final pipe = state.singleWhere((t) => t.issueId == 2);
    expect(fence.isRunning, isFalse);
    expect(fence.elapsed(now), const Duration(minutes: 30));
    expect(pipe.isRunning, isTrue);
    expect(state.where((t) => t.isRunning).length, 1);
  });

  test('switching back resumes where the timer left off', () async {
    final timers = await notifier();
    await timers.start(issueId: 1, projectId: 4, subject: 'Fence');
    now = now.add(const Duration(minutes: 10));
    await timers.start(issueId: 2, projectId: 4, subject: 'Pipe');
    now = now.add(const Duration(minutes: 60));

    await timers.start(issueId: 1, projectId: 4, subject: 'Fence');
    now = now.add(const Duration(minutes: 5));

    final state = container.read(timersProvider).value!;
    final fence = state.singleWhere((t) => t.issueId == 1);
    final pipe = state.singleWhere((t) => t.issueId == 2);
    expect(fence.elapsed(now), const Duration(minutes: 15));
    expect(pipe.elapsed(now), const Duration(minutes: 60));
    expect(pipe.isRunning, isFalse);
  });

  test('total tracked time never exceeds wall clock', () async {
    final timers = await notifier();
    final wallStart = now;
    await timers.start(issueId: 1, projectId: 4, subject: 'A');
    now = now.add(const Duration(minutes: 20));
    await timers.start(issueId: 2, projectId: 4, subject: 'B');
    now = now.add(const Duration(minutes: 40));
    await timers.start(issueId: 3, projectId: 4, subject: 'C');
    now = now.add(const Duration(minutes: 15));

    final state = container.read(timersProvider).value!;
    final total = state.fold(Duration.zero, (sum, t) => sum + t.elapsed(now));
    expect(total, now.difference(wallStart));
  });

  test('starting an already-running timer is a no-op', () async {
    final timers = await notifier();
    await timers.start(issueId: 1, projectId: 4, subject: 'Fence');
    now = now.add(const Duration(minutes: 5));

    final paused = await timers.start(
      issueId: 1,
      projectId: 4,
      subject: 'Fence',
    );

    expect(paused, isNull);
    expect(
      container
          .read(timersProvider)
          .value!
          .single
          .elapsed(now.add(const Duration(minutes: 5))),
      const Duration(minutes: 10),
    );
  });

  test('stop removes the timer and reports its total', () async {
    final timers = await notifier();
    await timers.start(issueId: 1, projectId: 4, subject: 'Fence');
    now = now.add(const Duration(minutes: 90));
    await timers.pause(1);
    now = now.add(const Duration(minutes: 30));

    final elapsed = await timers.stop(1);

    expect(
      elapsed,
      const Duration(minutes: 90),
      reason: 'paused time does not tick',
    );
    expect(container.read(timersProvider).value, isEmpty);
    expect(await timers.stop(1), isNull);
  });

  test('timers survive a restart, running stretch included', () async {
    final timers = await notifier();
    await timers.start(issueId: 1, projectId: 4, subject: 'Fence');
    now = now.add(const Duration(minutes: 10));

    // A new container over the same store file is "the app restarted".
    final revived = ProviderContainer(
      overrides: [
        timerStoreProvider.overrideWith((ref) async => store),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(revived.dispose);
    final state = await revived.read(timersProvider.future);

    final fence = state.single;
    expect(
      fence.isRunning,
      isTrue,
      reason: 'a running timer keeps running across restarts',
    );
    expect(fence.elapsed(now), const Duration(minutes: 10));
  });

  test('the model roundtrips through JSON', () {
    final timer = IssueTimer(
      issueId: 7,
      projectId: 4,
      subject: 'Fence',
      startedAt: DateTime.utc(2026, 8, 12, 9),
      accumulated: const Duration(minutes: 42),
      runningSince: DateTime.utc(2026, 8, 12, 10),
    );
    final revived = IssueTimer.fromJson(timer.toJson());
    expect(revived.issueId, 7);
    expect(revived.projectId, 4);
    expect(revived.subject, 'Fence');
    expect(revived.startedAt, timer.startedAt);
    expect(revived.accumulated, timer.accumulated);
    expect(revived.runningSince, timer.runningSince);
  });
}
