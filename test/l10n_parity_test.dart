import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every locale file must declare exactly the keys of the English template.
/// A missing translation is added by copying the English value, never by
/// leaving the key out.
void main() {
  test('all locale files declare the same keys as the template', () {
    final template = _keysOf(File('lib/l10n/app_en.arb'));
    final locales = Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.arb'))
        .where((file) => !file.path.endsWith('app_en.arb'));

    expect(locales, isNotEmpty, reason: 'no translated locale files found');

    for (final locale in locales) {
      final keys = _keysOf(locale);
      expect(
        keys,
        equals(template),
        reason: '${locale.path} is out of sync with app_en.arb',
      );
    }
  });
}

Set<String> _keysOf(File arb) {
  final content = json.decode(arb.readAsStringSync()) as Map<String, dynamic>;
  return content.keys.where((key) => !key.startsWith('@')).toSet();
}
