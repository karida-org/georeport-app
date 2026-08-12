import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/connections/scope_drift.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  group('newlyAdvertisedScopes', () {
    test('reports scopes the grant does not carry', () {
      expect(
        newlyAdvertisedScopes(
          granted: ['view_issues', 'edit_issues'],
          advertised: ['view_issues', 'edit_issues', 'log_time'],
        ),
        ['log_time'],
      );
    });

    test('no drift when the grant covers the advertised set', () {
      expect(
        newlyAdvertisedScopes(
          granted: ['edit_issues', 'view_issues'],
          advertised: ['view_issues', 'edit_issues'],
        ),
        isEmpty,
      );
    });

    test('a narrowed advertisement is not drift', () {
      expect(
        newlyAdvertisedScopes(
          granted: ['view_issues', 'log_time'],
          advertised: ['view_issues'],
        ),
        isEmpty,
      );
    });

    test('an unknown grant reports nothing rather than guessing', () {
      expect(
        newlyAdvertisedScopes(granted: [], advertised: ['view_issues']),
        isEmpty,
      );
    });
  });

  group('ScopeDriftDismissals', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test(
      'a dismissal holds for the same advertised set, in any order',
      () async {
        final dismissals = ScopeDriftDismissals();
        expect(await dismissals.isDismissed('c1', ['a', 'b']), isFalse);

        await dismissals.dismiss('c1', ['a', 'b']);
        expect(await dismissals.isDismissed('c1', ['b', 'a']), isTrue);
        expect(await dismissals.isDismissed('c2', ['a', 'b']), isFalse);
      },
    );

    test('a changed advertised set re-prompts', () async {
      final dismissals = ScopeDriftDismissals();
      await dismissals.dismiss('c1', ['a', 'b']);
      expect(await dismissals.isDismissed('c1', ['a', 'b', 'c']), isFalse);
    });

    test('clear forgets the record', () async {
      final dismissals = ScopeDriftDismissals();
      await dismissals.dismiss('c1', ['a']);
      await dismissals.clear('c1');
      expect(await dismissals.isDismissed('c1', ['a']), isFalse);
    });
  });
}
