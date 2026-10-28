/// Tests that `identityStoreProvider` and `tofuStoreProvider`
/// (app/lib/main.dart) are actually wired to the unlocked vault
/// environment's slot.
///
/// This is the fix for the coercion hole found in code review: Task 6 made
/// `IdentityStore`/`TofuStore` scopeable via `{int? environmentSlot}`, and
/// Task 7 built `VaultController`/`VaultState.slot`, but nothing connected
/// them — the providers in main.dart constructed unscoped stores
/// unconditionally, so Send and Receive always used the real identity no
/// matter which environment was unlocked. An attacker who coerces a user
/// into opening the decoy would still see the real Ed25519 fingerprint and
/// could correlate it with every file ever sent.
///
/// These tests exercise the providers directly through a `ProviderContainer`
/// (the normal way to test Riverpod providers without widgets), overriding
/// only `sodiumProvider`, `sodiumSumoProvider` and `vaultDirectoryProvider`
/// the way main() does, and driving `vaultControllerProvider`'s notifier
/// through real `unlock`/`lock` calls rather than poking state directly —
/// that's what proves the `ref.watch` rebuild chain, not just the
/// `IdentityStore(sodium, environmentSlot: ...)` construction, actually
/// works end to end.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/main.dart';
import 'package:dead_drop/ui/vault/vault_controller.dart';

/// In-memory fake for [FlutterSecureStoragePlatform], identical in spirit to
/// the one in environment_scoping_test.dart: `flutter_secure_storage` talks
/// to the OS keychain over a platform channel that doesn't exist in the
/// `flutter_tester` VM, so IdentityStore/TofuStore need a fake backing store
/// to exercise their real read/write/delete logic under `flutter test`.
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
  // VaultController registers itself as a WidgetsBindingObserver on
  // construction (see vault_controller.dart), which needs the test binding
  // initialized — otherwise WidgetsBinding.instance throws before the
  // provider even finishes building.
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumSumo sodium;
  late Directory tempDir;
  late _FakeSecureStorage fakeStorage;
  late ProviderContainer container;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('provider_scoping_test_');
    fakeStorage = _FakeSecureStorage();
    FlutterSecureStoragePlatform.instance = fakeStorage;

    container = ProviderContainer(
      overrides: [
        // sodiumProvider and sodiumSumoProvider deliberately share the same
        // sumo instance here, exactly as main() does when sumo is available
        // (SodiumSumo implements Sodium).
        sodiumProvider.overrideWithValue(sodium),
        sodiumSumoProvider.overrideWithValue(sodium),
        vaultDirectoryProvider.overrideWithValue(tempDir),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('no vault unlocked: identityStoreProvider yields the unscoped store',
      () async {
    final identityStore = container.read(identityStoreProvider);
    await identityStore.loadOrGenerate();

    expect(fakeStorage.data.keys, contains('deaddrop_identity_ed25519'));
    expect(fakeStorage.data.keys, isNot(anyElement(contains('_env'))));
  });

  test('no vault unlocked: tofuStoreProvider yields the unscoped store',
      () async {
    final tofuStore = container.read(tofuStoreProvider);
    await tofuStore.markKnown('aaaaaaaaaaaaaaaa');

    expect(fakeStorage.data.keys, contains('deaddrop_tofu_known_senders'));
    expect(fakeStorage.data.keys, isNot(anyElement(contains('_env'))));
  });

  test('unlocking slot 0 (real) keeps the same identity as no vault at all',
      () async {
    // The coercion hole this file was written for is the decoy seeing the
    // real fingerprint, which the slot 1 test below still pins. Slot 0 and
    // the no-vault case are not that: they are one device presenting
    // itself to the same people.
    //
    // Scoping them apart was reported as a bug from a real transfer — this
    // device's fingerprint changed depending on whether the vault happened
    // to be open, so correspondents had to confirm the same sender twice,
    // and the known-senders list went with it.
    final unscopedStore = container.read(identityStoreProvider);
    final unscopedIdentity = await unscopedStore.loadOrGenerate();

    final controller = container.read(vaultControllerProvider.notifier);
    await controller.createVault('correct horse battery staple');
    expect(container.read(vaultControllerProvider).slot, equals(0));

    final slot0Store = container.read(identityStoreProvider);
    final slot0Identity = await slot0Store.loadOrGenerate();

    expect(slot0Identity.fingerprint, equals(unscopedIdentity.fingerprint));
    expect(fakeStorage.data.keys,
        isNot(contains('deaddrop_identity_ed25519_env0')));
  });

  test(
      'unlocking slot 1 (decoy) yields an identity different from both '
      'slot 0 and the unscoped one', () async {
    final unscopedStore = container.read(identityStoreProvider);
    final unscopedIdentity = await unscopedStore.loadOrGenerate();

    final controller = container.read(vaultControllerProvider.notifier);
    await controller.createVault('correct horse battery staple');
    final slot0Store = container.read(identityStoreProvider);
    final slot0Identity = await slot0Store.loadOrGenerate();
    controller.lock();

    await controller.addDecoy('decoy passphrase entirely different');
    final ok = await controller.unlock('decoy passphrase entirely different');
    expect(ok, isTrue);
    expect(container.read(vaultControllerProvider).slot, equals(1));

    final slot1Store = container.read(identityStoreProvider);
    final slot1Identity = await slot1Store.loadOrGenerate();

    expect(slot1Identity.fingerprint, isNot(equals(slot0Identity.fingerprint)));
    expect(
        slot1Identity.fingerprint, isNot(equals(unscopedIdentity.fingerprint)));
    expect(fakeStorage.data.keys, contains('deaddrop_identity_ed25519_env1'));
  });

  test('locking returns identityStoreProvider to the unscoped identity',
      () async {
    final unscopedStore = container.read(identityStoreProvider);
    final unscopedIdentity = await unscopedStore.loadOrGenerate();

    final controller = container.read(vaultControllerProvider.notifier);
    await controller.createVault('correct horse battery staple');
    final slot0Store = container.read(identityStoreProvider);
    await slot0Store.loadOrGenerate();

    controller.lock();
    expect(container.read(vaultControllerProvider).slot, isNull);

    // Re-reading the provider after lock must hand back a store scoped to
    // null again — not the previous (slot 0) instance with its own
    // in-memory `_cached` identity still live.
    final postLockStore = container.read(identityStoreProvider);
    final postLockIdentity = await postLockStore.loadOrGenerate();

    expect(postLockIdentity.fingerprint, equals(unscopedIdentity.fingerprint));
  });

  test(
      'the decoy TOFU list does not show senders known to the real '
      'environment', () async {
    final controller = container.read(vaultControllerProvider.notifier);
    await controller.createVault('correct horse battery staple');

    final realTofu = container.read(tofuStoreProvider);
    await realTofu.markKnown('bbbbbbbbbbbbbbbb');
    expect(await realTofu.isKnown('bbbbbbbbbbbbbbbb'), isTrue);

    controller.lock();
    await controller.addDecoy('decoy passphrase entirely different');
    final ok = await controller.unlock('decoy passphrase entirely different');
    expect(ok, isTrue);

    final decoyTofu = container.read(tofuStoreProvider);
    expect(await decoyTofu.isKnown('bbbbbbbbbbbbbbbb'), isFalse);
    expect(await decoyTofu.count, equals(0));
  });
}
