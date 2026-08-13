import 'package:flutter_test/flutter_test.dart';
import 'package:georeport/src/api/base_url.dart';

void main() {
  group('normalizeBaseUrl', () {
    test('assumes https when the user leaves the scheme off', () {
      // What most people type. Defaulting to http instead would downgrade the
      // connection silently.
      expect(
        normalizeBaseUrl('redmine.example.org'),
        'https://redmine.example.org',
      );
    });

    test('keeps an explicit http, which local instances need', () {
      expect(normalizeBaseUrl('http://10.0.2.2:3000'), 'http://10.0.2.2:3000');
    });

    test('drops surrounding whitespace, as pasted URLs carry', () {
      expect(
        normalizeBaseUrl('  https://redmine.example.org  '),
        'https://redmine.example.org',
      );
    });

    test('drops trailing slashes, however many', () {
      // Paths are appended with a leading slash, so a trailing one here would
      // produce a double slash the server may or may not forgive.
      expect(
        normalizeBaseUrl('https://redmine.example.org/'),
        'https://redmine.example.org',
      );
      expect(
        normalizeBaseUrl('https://redmine.example.org///'),
        'https://redmine.example.org',
      );
    });

    test('keeps a sub-path, for instances not at the domain root', () {
      expect(
        normalizeBaseUrl('example.org/redmine/'),
        'https://example.org/redmine',
      );
    });

    test('passes an empty string straight through', () {
      // The empty field state. Turning it into "https://" would make an empty
      // form look like a configured one.
      expect(normalizeBaseUrl(''), '');
      expect(normalizeBaseUrl('   '), '');
    });

    test('is idempotent, since every layer normalizes independently', () {
      // The client, the OAuth config and the stored connection each call this.
      // If a second pass changed the result they could disagree about which
      // instance a session belongs to.
      const inputs = [
        'redmine.example.org',
        'https://redmine.example.org/',
        '  http://10.0.2.2:3000  ',
        'example.org/redmine/',
        '',
      ];
      for (final input in inputs) {
        final once = normalizeBaseUrl(input);
        expect(normalizeBaseUrl(once), once, reason: 'for input "$input"');
      }
    });
  });
}
