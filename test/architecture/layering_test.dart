import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files that are allowed to reach into `features/`, because composing the
/// app is exactly their job: the router names every screen, and the app
/// widget starts the feature that has to run from launch.
const _compositionRoot = {'lib/src/app.dart', 'lib/src/router.dart'};

final _import = RegExp(r"^import\s+'([^']+)'", multiLine: true);

void main() {
  test('core modules do not import features', () {
    // The layout is core modules (api, auth, capture, connections, issues,
    // location, map, ...) plus features/ for the screens on top. Features
    // depend on core; core must not depend on features.
    //
    // Not style: a cycle becomes possible the moment it goes both ways, and
    // core that knows about a feature cannot be exercised without dragging
    // that feature's providers in. This is checked rather than documented
    // because the individual violations each looked harmless.
    final violations = <String>[];

    for (final file in Directory('lib/src').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      // Normalized because Directory.listSync returns platform separators,
      // and on Windows this test would otherwise skip nothing and flag every
      // feature file, while never recognising the composition root.
      final path = file.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/src/features/') ||
          _compositionRoot.contains(path)) {
        continue;
      }
      for (final match in _import.allMatches(file.readAsStringSync())) {
        final target = match.group(1)!;
        if (target.contains('features/')) {
          violations.add('$path imports $target');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'A core module reached into features/. Move the shared piece into a '
          'core module, or invert it so core publishes and the feature '
          'subscribes (see draftSubmittedProvider for that shape).',
    );
  });
}
