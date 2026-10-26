/// Tests for the vault unlock path (app/lib/src/vault/vault_session.dart).
///
/// The property under test — constant derivation count regardless of
/// outcome — is the feature's headline guarantee: a coerced user typing the
/// decoy passphrase must cost an attacker-observable amount of work
/// identical to the real passphrase, a wrong passphrase, or an empty slot.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/vault/vault_keys.dart';
import 'package:dead_drop/src/vault/vault_session.dart';

void main() {
  late SodiumSumo sodium;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  group('tryUnlock', () {
    test('unlocks slot 0 with the real passphrase', () {
      final dataKey = newDataKey(sodium);
      final real = wrapDataKey(sodium, 'real passphrase', dataKey);
      final decoy = wrapDataKey(sodium, 'decoy passphrase', newDataKey(sodium));

      final result = tryUnlock(sodium, 'real passphrase', [real, decoy]);

      expect(result.ok, isTrue);
      expect(result.slotIndex, equals(0));
      expect(result.dataKey, equals(dataKey));
    });

    test('unlocks slot 1 with the decoy passphrase', () {
      final real = wrapDataKey(sodium, 'real passphrase', newDataKey(sodium));
      final decoyKey = newDataKey(sodium);
      final decoy = wrapDataKey(sodium, 'decoy passphrase', decoyKey);

      final result = tryUnlock(sodium, 'decoy passphrase', [real, decoy]);

      expect(result.ok, isTrue);
      expect(result.slotIndex, equals(1));
      expect(result.dataKey, equals(decoyKey));
    });

    test('returns not-ok for an unknown passphrase', () {
      final real = wrapDataKey(sodium, 'real passphrase', newDataKey(sodium));
      final decoy = wrapDataKey(sodium, 'decoy passphrase', newDataKey(sodium));

      final result = tryUnlock(sodium, 'wrong passphrase', [real, decoy]);

      expect(result.ok, isFalse);
      expect(result.slotIndex, isNull);
      expect(result.dataKey, isNull);
    });

    test(
        'attempts exactly kVaultEnvironmentSlots derivations regardless of '
        'outcome', () {
      final real = wrapDataKey(sodium, 'real passphrase', newDataKey(sodium));
      final decoy = wrapDataKey(sodium, 'decoy passphrase', newDataKey(sodium));
      final slots = [real, decoy];

      int countFor(String passphrase) {
        var count = 0;
        Uint8List? counting(
          SodiumSumo s,
          String p,
          WrappedKey w,
        ) {
          count++;
          return unwrapDataKey(s, p, w);
        }

        tryUnlock(sodium, passphrase, slots, unwrapDataKey: counting);
        return count;
      }

      final realCount = countFor('real passphrase');
      final decoyCount = countFor('decoy passphrase');
      final wrongCount = countFor('wrong passphrase');

      expect(realCount, equals(kVaultEnvironmentSlots));
      expect(decoyCount, equals(kVaultEnvironmentSlots));
      expect(wrongCount, equals(kVaultEnvironmentSlots));
    });

    test('an empty slot costs the same as a filled one', () {
      final real = wrapDataKey(sodium, 'real passphrase', newDataKey(sodium));
      final decoy = wrapDataKey(sodium, 'decoy passphrase', newDataKey(sodium));

      int countWith(List<WrappedKey?> slots, String passphrase) {
        var count = 0;
        Uint8List? counting(
          SodiumSumo s,
          String p,
          WrappedKey w,
        ) {
          count++;
          return unwrapDataKey(s, p, w);
        }

        tryUnlock(sodium, passphrase, slots, unwrapDataKey: counting);
        return count;
      }

      // A vault with a decoy...
      final withDecoyCount = countWith([real, decoy], 'real passphrase');
      // ...and a vault with no decoy at all...
      final withoutDecoyCount = countWith([real, null], 'real passphrase');

      // ...must spend identical derivation counts, or the absence of a
      // decoy becomes detectable.
      expect(withoutDecoyCount, equals(withDecoyCount));
      expect(withoutDecoyCount, equals(kVaultEnvironmentSlots));
    });
  });
}
