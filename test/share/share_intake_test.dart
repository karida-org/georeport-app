import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/share/share_channel.dart';
import 'package:georeport/src/share/share_intake.dart';

/// A channel the test feeds by hand; start() is a no-op.
class FakeShareChannel extends ShareChannel {
  final _controller = StreamController<List<String>>.broadcast();

  @override
  Stream<List<String>> get shares => _controller.stream;

  @override
  Future<void> start() async {}

  void emit(List<String> paths) => _controller.add(paths);
}

void main() {
  late FakeShareChannel channel;
  late List<List<String>> delivered;

  ProviderContainer harness({required bool connected}) {
    channel = FakeShareChannel();
    delivered = [];
    final container = ProviderContainer(
      overrides: [
        shareChannelProvider.overrideWithValue(channel),
        hasActiveConnectionProvider.overrideWithValue(connected),
        shareNavigatorProvider.overrideWithValue(delivered.add),
      ],
    );
    addTearDown(container.dispose);
    container.read(shareIntakeProvider);
    return container;
  }

  test('a share with an active session opens capture immediately', () async {
    harness(connected: true);

    channel.emit(['/cache/a.jpg']);
    await Future<void>.delayed(Duration.zero);

    expect(delivered, [
      ['/cache/a.jpg'],
    ]);
  });

  test('a share without a session waits for the connection', () async {
    final container = harness(connected: false);

    channel.emit(['/cache/a.jpg']);
    await Future<void>.delayed(Duration.zero);
    expect(delivered, isEmpty);
    expect(container.read(shareIntakeProvider), ['/cache/a.jpg']);

    container.updateOverrides([
      shareChannelProvider.overrideWithValue(channel),
      hasActiveConnectionProvider.overrideWithValue(true),
      shareNavigatorProvider.overrideWithValue(delivered.add),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(delivered, [
      ['/cache/a.jpg'],
    ]);
    expect(container.read(shareIntakeProvider), isEmpty);
  });

  test('consecutive shares accumulate until delivery', () async {
    final container = harness(connected: false);

    channel.emit(['/cache/a.jpg']);
    channel.emit(['/cache/b.jpg']);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(shareIntakeProvider), [
      '/cache/a.jpg',
      '/cache/b.jpg',
    ]);
  });
}
