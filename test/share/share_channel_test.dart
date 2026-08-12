import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/share/share_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('georeport/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('drains the initial share that cold-started the app', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return call.method == 'getInitialShare' ? ['/cache/a.jpg'] : null;
    });
    final share = ShareChannel();
    final events = <List<String>>[];
    share.shares.listen(events.add);

    await share.start();
    await Future<void>.delayed(Duration.zero);

    expect(events, [
      ['/cache/a.jpg'],
    ]);
  });

  test('streams shares pushed while the app is running', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => <String>[]);
    final share = ShareChannel();
    final events = <List<String>>[];
    share.shares.listen(events.add);
    await share.start();

    await messenger.handlePlatformMessage(
      'georeport/share',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('shared', ['/cache/b.jpg', '/cache/c.jpg']),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, [
      ['/cache/b.jpg', '/cache/c.jpg'],
    ]);
  });

  test('start survives a platform without a share handler', () async {
    // No mock handler set: the invoke raises MissingPluginException.
    final share = ShareChannel();
    await expectLater(share.start(), completes);
  });
}
