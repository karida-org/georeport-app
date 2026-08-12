import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/features/capture/capture_defaults.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('remembers the last project and the last tracker per project', () async {
    final defaults = CaptureDefaults();
    expect(await defaults.lastProject(), isNull);
    expect(await defaults.lastTracker(1), isNull);

    await defaults.remember(projectId: 1, trackerId: 4);
    await defaults.remember(projectId: 2, trackerId: 7);

    expect(await defaults.lastProject(), 2);
    expect(await defaults.lastTracker(1), 4);
    expect(await defaults.lastTracker(2), 7);
  });
}
