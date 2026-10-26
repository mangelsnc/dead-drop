/// Tests for environment-scoped identity and TOFU storage
/// (app/lib/src/identity_store.dart, app/lib/src/tofu_store.dart).
///
/// Without scoping, opening the decoy vault would show the real
/// environment's signing identity and known-sender history, letting an
/// attacker correlate every file ever sent across environments. These tests
/// verify each environment slot gets its own storage, and that the no-vault
/// (unscoped) path is untouched so existing installs see no behaviour change.
library;


import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium.dart' show Sodium;
import 'package:sodium/sodium.dart' show SodiumInit;

import 'package:dead_drop/src/identity_store.dart';
import 'package:dead_drop/src/tofu_store.dart';

/// In-memory fake for [FlutterSecureStoragePlatform].
///
/// `flutter_secure_storage` talks to the OS keychain over a platform
/// channel, which doesn't exist in the `flutter_tester` VM used by `flutter
/// test`. Swapping in this fake lets IdentityStore/TofuStore exercise their
/// real read/write/delete logic against a plain in-memory map instead.
class _FakeSecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> data = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    data[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    return data[key];
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    return data.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    data.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    return Map.of(data);
  }

  @override
  Future<void> deleteAll({
    required Map<String, String> options,
  }) async {
    data.clear();
  }
}

void main() {
  late Sodium sodium;
  late _FakeSecureStorage fakeStorage;

  setUpAll(() async {
    sodium = await SodiumInit.init();
  });

  setUp(() {
    // Fresh in-memory backing store for every test so they can't see each
    // other's writes.
    fakeStorage = _FakeSecureStorage();
    FlutterSecureStoragePlatform.instance = fakeStorage;
  });

  group('IdentityStore environment scoping', () {
    test('identities in different environments are different', () async {
      final storeA = IdentityStore(sodium, environmentSlot: 0);
      final storeB = IdentityStore(sodium, environmentSlot: 1);

      final identityA = await storeA.loadOrGenerate();
      final identityB = await storeB.loadOrGenerate();

      expect(identityA.fingerprint, isNot(equals(identityB.fingerprint)));
      // And each was persisted under its own key.
      expect(fakeStorage.data.keys,
          containsAll(['deaddrop_identity_ed25519_env0', 'deaddrop_identity_ed25519_env1']));
    });

    test('the no-vault identity keeps the existing storage key', () async {
      final store = IdentityStore(sodium);
      await store.loadOrGenerate();

      expect(fakeStorage.data.keys, contains('deaddrop_identity_ed25519'));
      expect(
        fakeStorage.data.keys,
        isNot(anyElement(contains('_env'))),
      );
    });

    test('the same environment slot reloads the same identity', () async {
      final first = IdentityStore(sodium, environmentSlot: 3);
      final identity = await first.loadOrGenerate();

      // A fresh instance (no in-memory cache) pointed at the same slot
      // should read back the persisted identity, not generate a new one.
      final second = IdentityStore(sodium, environmentSlot: 3);
      final reloaded = await second.loadOrGenerate();

      expect(reloaded.fingerprint, equals(identity.fingerprint));
    });
  });

  group('TofuStore environment scoping', () {
    test('TOFU entries do not leak between environments', () async {
      final storeA = TofuStore(environmentSlot: 0);
      final storeB = TofuStore(environmentSlot: 1);

      await storeA.markKnown('aaaaaaaaaaaaaaaa');

      expect(await storeA.isKnown('aaaaaaaaaaaaaaaa'), isTrue);
      expect(await storeB.isKnown('aaaaaaaaaaaaaaaa'), isFalse);
      expect(await storeB.count, equals(0));
    });

    test('the no-vault TOFU store keeps the existing storage key', () async {
      final store = TofuStore();
      await store.markKnown('bbbbbbbbbbbbbbbb');

      expect(fakeStorage.data.keys, contains('deaddrop_tofu_known_senders'));
      expect(
        fakeStorage.data.keys,
        isNot(anyElement(contains('_env'))),
      );
    });

    test('two instances scoped to the same slot do not share a cache, '
        'but do share persisted state', () async {
      final first = TofuStore(environmentSlot: 2);
      await first.markKnown('cccccccccccccccc');

      // A second instance for the same slot has its own _cached field, so
      // this exercises an actual read from the backing store rather than a
      // hit on a shared in-memory cache.
      final second = TofuStore(environmentSlot: 2);
      expect(await second.isKnown('cccccccccccccccc'), isTrue);
    });
  });
}
