/// Tests for the vault session controller
/// (app/lib/ui/vault/vault_controller.dart).
///
/// This is the integration point between the crypto/storage layers and the
/// UI: it owns the open environment's data key and the decrypted entry
/// list, and is responsible for making both disappear the moment the vault
/// should no longer be considered open — whether that's an explicit
/// `lock()` or the app being backgrounded (Review Focus #2).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/vault/vault_session.dart';
import 'package:dead_drop/src/vault/vault_store.dart';
import 'package:dead_drop/src/vault/attempt_guard.dart';
import 'package:dead_drop/src/vault/vault_keys.dart';
import 'package:dead_drop/ui/vault/vault_controller.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

/// Recovers the data key for [passphrase] against [slots], for test setup
/// that needs to write directly through [VaultStore] rather than through
/// the controller (whose public surface deliberately has no `put`/`get` —
/// that's Task 9's job).
Uint8List tryUnlockFor(
  SodiumSumo sodium,
  String passphrase,
  List<dynamic> slots,
) {
  final result = tryUnlock(sodium, passphrase, slots.cast());
  if (!result.ok) {
    throw StateError('test setup: $passphrase did not unlock any slot');
  }
  return result.dataKey!;
}

/// In-memory keychain: `flutter_secure_storage` talks to the OS over a
/// platform channel that does not exist in `flutter_tester`.
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
  }) async =>
      data[key];

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      data.containsKey(key);

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
  }) async =>
      Map.of(data);

  @override
  Future<void> deleteAll({
    required Map<String, String> options,
  }) async {
    data.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumSumo sodium;
  late Directory tempDir;
  late _FakeSecureStorage keychain;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('vault_controller_test_');

    // A fresh in-memory keychain per test.
    //
    // `FlutterSecureStoragePlatform.instance` is a global. AttemptGuard
    // reads the failed-attempt counter through it, so a test that leaves
    // the counter at the self-destruct threshold makes every later test in
    // this file serve the capped 60s penalty and time out. Installing a new
    // fake here — rather than only in the one test that needs it — keeps
    // each test independent, and keeps all of them off the host keychain,
    // which no test has any business writing to.
    keychain = _FakeSecureStorage();
    FlutterSecureStoragePlatform.instance = keychain;
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  VaultController buildController() {
    final store = VaultStore(tempDir, sodium);
    return VaultController(sodium, store);
  }

  test(
      'self-destruct at the threshold destroys every slot, and says nothing '
      'an ordinary wrong passphrase would not', () async {
    // The most safety-critical behaviour in the feature, and the one that
    // had no coverage: a surviving decoy would prove to an attacker that
    // there had been something to erase.
    keychain.data[kSelfDestructStorageKey] = 'true';

    final store = VaultStore(tempDir, sodium);
    final controller = VaultController(
      sodium,
      store,
      // No delay: the production curve would make this test wait nearly
      // four minutes of real time to cross the threshold. The counting and
      // the wipe are unaffected — only the waiting is.
      attemptGuard: AttemptGuard(
        storage: const FlutterSecureStorage(),
        penaltyStep: Duration.zero,
      ),
    );
    addTearDown(controller.dispose);

    await controller.createVault('correct horse battery staple six');
    await controller.addDecoy('seven eight nine ten eleven twelve');
    controller.lock();

    // A success resets the counter, so the run of failures that crosses the
    // threshold has to be unbroken. Check that reset explicitly first —
    // it is the reason a naive version of this test never fires at all.
    for (var i = 0; i < kSelfDestructThreshold - 1; i++) {
      await controller.unlock('wrong passphrase $i');
    }
    expect(await controller.unlock('correct horse battery staple six'), isTrue,
        reason: 'one short of the threshold, the vault still opens');
    controller.lock();

    // Now an unbroken run all the way to the threshold.
    for (var i = 0; i < kSelfDestructThreshold - 1; i++) {
      final fired = await controller.unlock('still wrong $i');
      expect(fired, isFalse);
    }
    final crossed = await controller.unlock('one wrong too many');
    expect(crossed, isFalse);
    expect(controller.state.error, 'Incorrect passphrase',
        reason: 'the wipe must not announce itself');

    // The wipe is deliberately not awaited inside unlock() so it cannot be
    // timed; wait for it here before checking the slots.
    await controller.debugWipe;

    expect(await controller.unlock('correct horse battery staple six'), isFalse,
        reason: 'the real environment must be gone');
    expect(await controller.unlock('seven eight nine ten eleven twelve'),
        isFalse,
        reason: 'the decoy must be gone too — a survivor proves there was '
            'something to erase');

    // Let any straggling wipe I/O settle before tearDown removes the temp
    // directory out from under it.
    await controller.debugWipe;

    final slots = await store.readSlots();
    expect(slots, hasLength(kVaultEnvironmentSlots));
    for (final slot in slots) {
      expect(slot, isA<WrappedKey>(),
          reason: 'destroyed slots still parse as filler: the on-disk shape '
              'must not reveal that a wipe happened');
    }
  });

  test('a vault survives the app being closed and reopened', () async {
    // Reported from a device: create a vault, fully close the app (not
    // just background it), reopen — and the vault was gone from the
    // interface. No entry, no unlock prompt, no vault option when saving
    // a received file. The data was always on disk; nothing in the UI
    // could reach it, because `exists` was only ever set by createVault
    // and unlock, both of which happen within a single session.
    final first = buildController();
    await first.createVault('correct horse battery staple six');
    expect(first.state.exists, isTrue);
    first.dispose();

    // A fresh controller over the same directory, as on the next launch.
    final reopened = buildController();
    addTearDown(reopened.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(reopened.state.exists, isTrue,
        reason: 'a configured vault must still be reachable after a '
            'restart');
    expect(reopened.state.unlocked, isFalse,
        reason: 'but still locked — knowing one exists is not knowing the '
            'passphrase');
    expect(await reopened.unlock('correct horse battery staple six'), isTrue);
  });

  test('no vault means no vault, after a restart too', () async {
    // The other direction: a directory nobody has set up must not start
    // claiming a vault exists, or the home screen would show an entry
    // that opens nothing.
    final controller = buildController();
    addTearDown(controller.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.state.exists, isFalse);
  });

  test('unlock with the real passphrase exposes the real entries', () async {
    final controller = buildController();
    addTearDown(controller.dispose);
    final store = VaultStore(tempDir, sodium);

    await controller.createVault('correct horse battery staple');
    // Seed an entry directly through the store, the way Task 9's save path
    // eventually will — the controller's job here is exposing it on
    // unlock, not writing it.
    final realKey = await store.readSlots();
    final dataKey =
        tryUnlockFor(sodium, 'correct horse battery staple', realKey);
    await store.put(dataKey, 0, 'note.txt', _bytes([1, 2, 3]));
    controller.lock();

    final ok = await controller.unlock('correct horse battery staple');

    expect(ok, isTrue);
    expect(controller.state.unlocked, isTrue);
    expect(controller.state.slot, equals(0));
    expect(controller.state.entries, hasLength(1));
    expect(controller.state.entries.single.name, equals('note.txt'));
  });

  test('unlock with the decoy passphrase exposes the decoy entries', () async {
    final controller = buildController();
    addTearDown(controller.dispose);
    final store = VaultStore(tempDir, sodium);

    await controller.createVault('correct horse battery staple');
    final realSlots = await store.readSlots();
    final realKey =
        tryUnlockFor(sodium, 'correct horse battery staple', realSlots);
    await store.put(realKey, 0, 'real.txt', _bytes([1]));
    controller.lock();

    await controller.addDecoy('decoy passphrase entirely different');
    final decoySlots = await store.readSlots();
    final decoyKey =
        tryUnlockFor(sodium, 'decoy passphrase entirely different', decoySlots);
    await store.put(decoyKey, 1, 'decoy.txt', _bytes([2]));

    final ok = await controller.unlock('decoy passphrase entirely different');

    expect(ok, isTrue);
    expect(controller.state.slot, equals(1));
    expect(controller.state.entries, hasLength(1));
    expect(controller.state.entries.single.name, equals('decoy.txt'));
  });

  test('lock() clears the data key and the entry list from memory', () async {
    final controller = buildController();
    addTearDown(controller.dispose);
    final store = VaultStore(tempDir, sodium);

    await controller.createVault('correct horse battery staple');
    final slots = await store.readSlots();
    final dataKey = tryUnlockFor(sodium, 'correct horse battery staple', slots);
    await store.put(dataKey, 0, 'secret.txt', _bytes([9, 9, 9]));
    // Re-unlock so the controller's own state reflects the seeded entry.
    await controller.unlock('correct horse battery staple');
    expect(controller.state.unlocked, isTrue);
    expect(controller.state.entries, isNotEmpty);

    controller.lock();

    expect(controller.state.unlocked, isFalse);
    expect(controller.state.slot, isNull);
    expect(controller.state.entries, isEmpty);
    // The data key itself must be gone, not just unreachable from state: a
    // post-lock get() against the store with the old key must still work
    // (the key material is independent of the store), but the controller
    // must no longer hold a reference to it at all — verified via the
    // internal accessor exposed only to this test file.
    expect(controller.debugHasDataKey, isFalse);
  });

  test('the vault locks when the app is backgrounded', () async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await controller.createVault('correct horse battery staple');
    expect(controller.state.unlocked, isTrue);

    // Drive the real dispatch path rather than calling
    // didChangeAppLifecycleState directly: WidgetsBinding.handleApp
    // LifecycleStateChanged iterates its registered observer list and
    // invokes didChangeAppLifecycleState on each one (see
    // packages/flutter/lib/src/widgets/binding.dart). Going through the
    // binding is what actually proves the controller's constructor-time
    // `WidgetsBinding.instance.addObserver(this)` registered it — calling
    // the method directly on the controller would pass even if
    // registration were broken (wrong list, double-dispose, swapped
    // binding), since it never touches the binding at all.
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );

    expect(controller.state.unlocked, isFalse);
    expect(controller.state.entries, isEmpty);
    expect(controller.debugHasDataKey, isFalse);
  });

  test('createVault does not require a decoy', () async {
    final controller = buildController();
    addTearDown(controller.dispose);

    await controller.createVault('correct horse battery staple');

    expect(controller.state.exists, isTrue);
    expect(controller.state.unlocked, isTrue);
    expect(controller.state.slot, equals(0));
    expect(controller.state.entries, isEmpty);

    // A passphrase that would only ever match a decoy slot finds nothing,
    // because none was ever provisioned — this must not throw or crash.
    controller.lock();
    final ok = await controller.unlock('nonexistent decoy passphrase');
    expect(ok, isFalse);
  });

  test('createVault refuses to clobber an existing vault or its decoy',
      () async {
    final controller = buildController();
    addTearDown(controller.dispose);
    final store = VaultStore(tempDir, sodium);

    await controller.createVault('correct horse battery staple');
    await controller.addDecoy('decoy passphrase entirely different');

    // A second createVault call on the same controller — e.g. a UI
    // double-tap — must not overwrite slot 0 or wipe out the decoy in slot
    // 1. (The guard is necessarily session-local: the on-disk slot files are
    // indistinguishable whether or not they hold a real environment, by
    // design — see vault_store.dart — so VaultState.exists, not a disk
    // read, is what createVault can check here.)
    await controller.createVault('a brand new different passphrase');

    expect(controller.state.error, isNotNull);

    final slots = await store.readSlots();
    final realKey = tryUnlockFor(sodium, 'correct horse battery staple', slots);
    final decoyKey =
        tryUnlockFor(sodium, 'decoy passphrase entirely different', slots);
    expect(realKey, isNotNull);
    expect(decoyKey, isNotNull);

    // The new passphrase must not have replaced either slot.
    final result =
        tryUnlock(sodium, 'a brand new different passphrase', slots.cast());
    expect(result.ok, isFalse);
  });
}
