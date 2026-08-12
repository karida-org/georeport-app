import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/auth/pkce.dart';

void main() {
  test('generates an RFC 7636 verifier and S256 challenge', () {
    final pair = PkcePair.generate();

    expect(pair.verifier.length, 64);
    expect(pair.verifier, matches(RegExp(r'^[A-Za-z0-9\-._~]+$')));
    final expected = base64UrlEncode(
      sha256.convert(ascii.encode(pair.verifier)).bytes,
    ).replaceAll('=', '');
    expect(pair.challenge, expected);
    expect(pair.challenge, isNot(contains('=')));
  });

  test('pairs are unique', () {
    expect(PkcePair.generate().verifier, isNot(PkcePair.generate().verifier));
  });
}
