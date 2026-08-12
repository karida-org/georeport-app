import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A PKCE verifier/challenge pair (RFC 7636, S256).
class PkcePair {
  PkcePair._(this.verifier, this.challenge);

  factory PkcePair.generate({Random? random}) {
    final rng = random ?? Random.secure();
    final verifier = List.generate(
      64,
      (_) => _unreserved[rng.nextInt(_unreserved.length)],
    ).join();
    final challenge = base64UrlEncode(
      sha256.convert(ascii.encode(verifier)).bytes,
    ).replaceAll('=', '');
    return PkcePair._(verifier, challenge);
  }

  static const _unreserved =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  final String verifier;
  final String challenge;
}
