/// Tests for the Argon2id key-derivation wrapper (app/lib/src/vault/pwhash.dart).
library;


import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/vault/pwhash.dart';

void main() {
  late SodiumSumo sodium;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  group('deriveKek', () {
    test('is deterministic for the same passphrase and salt', () {
      final salt = newSalt(sodium);
      final a = deriveKek(sodium, 'correct horse battery staple', salt);
      final b = deriveKek(sodium, 'correct horse battery staple', salt);
      try {
        expect(a.extractBytes(), equals(b.extractBytes()));
      } finally {
        a.dispose();
        b.dispose();
      }
    });

    test('differs when the salt differs', () {
      final saltA = newSalt(sodium);
      final saltB = newSalt(sodium);
      final a = deriveKek(sodium, 'correct horse battery staple', saltA);
      final b = deriveKek(sodium, 'correct horse battery staple', saltB);
      try {
        expect(a.extractBytes(), isNot(equals(b.extractBytes())));
      } finally {
        a.dispose();
        b.dispose();
      }
    });

    test('differs when the passphrase differs', () {
      final salt = newSalt(sodium);
      final a = deriveKek(sodium, 'correct horse battery staple', salt);
      final b = deriveKek(sodium, 'correct horse battery staple!', salt);
      try {
        expect(a.extractBytes(), isNot(equals(b.extractBytes())));
      } finally {
        a.dispose();
        b.dispose();
      }
    });

    test('returns a 32-byte SecureKey', () {
      final salt = newSalt(sodium);
      final key = deriveKek(sodium, 'correct horse battery staple', salt);
      try {
        expect(key.length, 32);
      } finally {
        key.dispose();
      }
    });

    test('returned key is usable and disposable', () {
      // Covers the hardening fix: deriveKek returns a SecureKey (not raw
      // bytes) so the KEK never sits unprotected in pageable heap memory.
      // The caller must be able to read it via extractBytes() and dispose
      // it without error.
      final salt = newSalt(sodium);
      final key = deriveKek(sodium, 'correct horse battery staple', salt);
      expect(key, isA<SecureKey>());
      expect(() => key.extractBytes(), returnsNormally);
      expect(() => key.dispose(), returnsNormally);
    });
  });

  group('newSalt', () {
    test('returns kVaultSaltBytes of non-constant output', () {
      final a = newSalt(sodium);
      final b = newSalt(sodium);
      expect(a, hasLength(kVaultSaltBytes));
      expect(b, hasLength(kVaultSaltBytes));
      expect(a, isNot(equals(b)));
    });
  });
}
