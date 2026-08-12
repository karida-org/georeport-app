import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/features/location/location_sharing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('sharing is off until the user turns it on', () async {
    final preference = LocationSharingPreference();
    expect(await preference.isEnabled('c1'), isFalse);

    await preference.setEnabled('c1', enabled: true);

    expect(await preference.isEnabled('c1'), isTrue);
  });

  test('the choice is per connection, never shared across instances', () async {
    final preference = LocationSharingPreference();
    await preference.setEnabled('c1', enabled: true);

    expect(await preference.isEnabled('c2'), isFalse);
  });

  test('forgetting a connection forgets its choice', () async {
    final preference = LocationSharingPreference();
    await preference.setEnabled('c1', enabled: true);

    await preference.clear('c1');

    expect(await preference.isEnabled('c1'), isFalse);
  });

  test('turning sharing off is remembered, not just dropped', () async {
    final preference = LocationSharingPreference();
    await preference.setEnabled('c1', enabled: true);
    await preference.setEnabled('c1', enabled: false);

    expect(await preference.isEnabled('c1'), isFalse);
  });
}
