/// Tests for the vault key hierarchy (app/lib/src/vault/vault_keys.dart).
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/vault/vault_keys.dart';

void main() {
  late SodiumSumo sodium;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  group('wrapDataKey / unwrapDataKey', () {
    test('wrap then unwrap with the same passphrase returns the data key', () {
      final dataKey = newDataKey(sodium);
      final wrapped =
          wrapDataKey(sodium, 'correct horse battery staple', dataKey);

      final unwrapped =
          unwrapDataKey(sodium, 'correct horse battery staple', wrapped);

      expect(unwrapped, equals(dataKey));
    });

    test('unwrap with a wrong passphrase returns null, does not throw', () {
      final dataKey = newDataKey(sodium);
      final wrapped =
          wrapDataKey(sodium, 'correct horse battery staple', dataKey);

      Uint8List? unwrapped;
      expect(
        () => unwrapped = unwrapDataKey(sodium, 'wrong passphrase', wrapped),
        returnsNormally,
      );
      expect(unwrapped, isNull);
    });

    test('two wraps of the same key differ (fresh salt and nonce)', () {
      final dataKey = newDataKey(sodium);
      final a = wrapDataKey(sodium, 'correct horse battery staple', dataKey);
      final b = wrapDataKey(sodium, 'correct horse battery staple', dataKey);

      expect(a.salt, isNot(equals(b.salt)));
      expect(a.nonce, isNot(equals(b.nonce)));
      expect(a.ciphertext, isNot(equals(b.ciphertext)));
    });
  });

  group('WrappedKey.pack / unpack', () {
    test('pack/unpack round-trips a WrappedKey', () {
      final dataKey = newDataKey(sodium);
      final wrapped =
          wrapDataKey(sodium, 'correct horse battery staple', dataKey);

      final roundTripped = WrappedKey.unpack(wrapped.pack());

      expect(roundTripped.salt, equals(wrapped.salt));
      expect(roundTripped.nonce, equals(wrapped.nonce));
      expect(roundTripped.ciphertext, equals(wrapped.ciphertext));

      // And the round-tripped WrappedKey must still unwrap correctly.
      final unwrapped =
          unwrapDataKey(sodium, 'correct horse battery staple', roundTripped);
      expect(unwrapped, equals(dataKey));
    });

    test(
        'unpack on bytes truncated within the salt/nonce header throws '
        'MalformedWrappedKeyException, not RangeError', () {
      final dataKey = newDataKey(sodium);
      final wrapped =
          wrapDataKey(sodium, 'correct horse battery staple', dataKey);
      final packed = wrapped.pack();

      // The header is [salt len][salt][nonce len][nonce]; anything shorter
      // than that cannot possibly be a well-formed WrappedKey. Once the
      // header is complete, unpack can no longer tell a short-but-present
      // ciphertext from a deliberately tiny one — that's caught downstream
      // by the secretbox authentication check in unwrapDataKey, not here.
      final headerLength = 1 + wrapped.salt.length + 1 + wrapped.nonce.length;

      for (var cutAt = 0; cutAt < headerLength; cutAt++) {
        final truncated = packed.sublist(0, cutAt);
        expect(
          () => WrappedKey.unpack(truncated),
          throwsA(isA<MalformedWrappedKeyException>()),
          reason: 'truncating to $cutAt bytes should fail cleanly',
        );
      }
    });

    test(
        'unpack on bytes truncated to no ciphertext at all throws '
        'MalformedWrappedKeyException', () {
      final dataKey = newDataKey(sodium);
      final wrapped =
          wrapDataKey(sodium, 'correct horse battery staple', dataKey);
      final packed = wrapped.pack();
      final headerLength = 1 + wrapped.salt.length + 1 + wrapped.nonce.length;

      expect(
        () => WrappedKey.unpack(packed.sublist(0, headerLength)),
        throwsA(isA<MalformedWrappedKeyException>()),
      );
    });

    test(
        'unpack on bytes truncated to a ciphertext shorter than a secretbox '
        'MAC throws MalformedWrappedKeyException, not a bare RangeError', () {
      final dataKey = newDataKey(sodium);
      final wrapped =
          wrapDataKey(sodium, 'correct horse battery staple', dataKey);
      final packed = wrapped.pack();
      final headerLength = 1 + wrapped.salt.length + 1 + wrapped.nonce.length;

      // Exactly one byte of "ciphertext" — present, but far short of a
      // secretbox MAC (16 bytes), which is what `secretBox.openEasy` itself
      // would reject with a bare RangeError if unpack let it through.
      expect(
        () => WrappedKey.unpack(packed.sublist(0, headerLength + 1)),
        throwsA(isA<MalformedWrappedKeyException>()),
      );
    });

    test(
        'unpack on bytes with exactly a MAC-sized ciphertext parses, but '
        'the result fails to authenticate', () {
      final dataKey = newDataKey(sodium);
      final wrapped =
          wrapDataKey(sodium, 'correct horse battery staple', dataKey);
      final packed = wrapped.pack();
      final headerLength = 1 + wrapped.salt.length + 1 + wrapped.nonce.length;
      const macBytes = 16;

      final truncated =
          WrappedKey.unpack(packed.sublist(0, headerLength + macBytes));
      expect(
        unwrapDataKey(sodium, 'correct horse battery staple', truncated),
        isNull,
      );
    });

    test('unpack on empty bytes throws MalformedWrappedKeyException', () {
      expect(
        () => WrappedKey.unpack(Uint8List(0)),
        throwsA(isA<MalformedWrappedKeyException>()),
      );
    });
  });

  group('newDataKey', () {
    test('returns 32 bytes of non-constant output', () {
      final a = newDataKey(sodium);
      final b = newDataKey(sodium);
      expect(a, hasLength(32));
      expect(b, hasLength(32));
      expect(a, isNot(equals(b)));
    });
  });
}
