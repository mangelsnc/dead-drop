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

  group('deleting the vault', () {
    test('erases both environments, whichever passphrase opened it',
        () async {
      // The property the whole design rests on. Erasing only the
      // environment whose passphrase was typed would leave the other
      // behind — and a user coerced into deleting "their vault" with the
      // decoy passphrase would have handed the attacker a device that
      // still holds the real one.
      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.createVault('correct horse battery staple six');
      await controller.addDecoy('seven eight nine ten eleven twelve');

      final store = VaultStore(tempDir, sodium);
      final realKey =
          tryUnlockFor(sodium, 'correct horse battery staple six',
              await store.readSlots());
      await store.put(realKey, 0, 'real.txt', _bytes([1, 2, 3]));

      controller.lock();

      // Deleted with the DECOY passphrase.
      expect(
        await controller.deleteVault('seven eight nine ten eleven twelve'),
        isTrue,
      );

      // Neither passphrase opens anything afterwards.
      expect(await controller.unlock('seven eight nine ten eleven twelve'),
          isFalse);
      expect(await controller.unlock('correct horse battery staple six'),
          isFalse);
    });

    test('leaves nothing on disk', () async {
      // Not a tidiness check: a directory still holding one slot file, or
      // an entries/ directory with sealed files in it, says a vault was
      // here and roughly how much was in it. "Deleted" has to mean the
      // shape is gone too.
      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.createVault('correct horse battery staple six');
      await controller.addDecoy('seven eight nine ten eleven twelve');

      final store = VaultStore(tempDir, sodium);
      final slots = await store.readSlots();
      await store.put(tryUnlockFor(sodium, 'correct horse battery staple six',
              slots), 0, 'real.txt', _bytes([1, 2, 3]));
      await store.put(tryUnlockFor(sodium, 'seven eight nine ten eleven twelve',
              slots), 1, 'decoy.txt', _bytes([4, 5, 6]));

      expect(await controller.deleteVault('correct horse battery staple six'),
          isTrue);

      final survivors = tempDir.existsSync()
          ? tempDir.listSync(recursive: true).map((e) => e.path).toList()
          : <String>[];
      expect(survivors, isEmpty, reason: 'survivors: $survivors');
    });

    test('a wrong passphrase deletes nothing', () async {
      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.createVault('correct horse battery staple six');
      controller.lock();

      expect(await controller.deleteVault('not the passphrase at all'),
          isFalse);
      expect(controller.state.error, 'Incorrect passphrase');

      // The vault is untouched: the real passphrase still opens it.
      expect(await controller.unlock('correct horse battery staple six'),
          isTrue);
    });

    test('an erased vault leaves no vault for the next launch to find',
        () async {
      // The restore-on-start path reads the store directly. If deletion
      // left it answering "yes" the home screen would offer a vault that
      // cannot be opened — the mirror of the bug that made a real vault
      // invisible after a restart.
      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.createVault('correct horse battery staple six');
      expect(await VaultStore(tempDir, sodium).hasBeenSetUp(), isTrue);

      await controller.deleteVault('correct horse battery staple six');

      expect(await VaultStore(tempDir, sodium).hasBeenSetUp(), isFalse);
      expect(controller.state.exists, isFalse);
      expect(controller.state.unlocked, isFalse);
    });

    test('drops the open data key', () async {
      // Deleting while unlocked must not leave the key for the erased
      // environment sitting in memory.
      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.createVault('correct horse battery staple six');
      expect(await controller.unlock('correct horse battery staple six'),
          isTrue);
      expect(controller.debugHasDataKey, isTrue);

      await controller.deleteVault('correct horse battery staple six');

      expect(controller.debugHasDataKey, isFalse);
    });

    test('a vault created afterwards does not inherit self-destruct',
        () async {
      // Self-destruct is opt-in and destructive. A preference surviving
      // the vault it was set on would arm a new vault nobody armed.
      keychain.data[kSelfDestructStorageKey] = 'true';

      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.createVault('correct horse battery staple six');
      await controller.deleteVault('correct horse battery staple six');

      expect(keychain.data[kSelfDestructStorageKey], isNot('true'));
    });

    test('a failed delete counts as a failed attempt', () async {
      // Otherwise the delete dialog is a rate-limit-free oracle for
      // guessing a passphrase: unlimited guesses, and each one reports
      // whether it was right.
      final guard = AttemptGuard(
        storage: const FlutterSecureStorage(),
        penaltyStep: Duration.zero,
      );
      final controller =
          VaultController(sodium, VaultStore(tempDir, sodium),
              attemptGuard: guard);
      addTearDown(controller.dispose);

      await controller.createVault('correct horse battery staple six');
      final before = await guard.failureCount();

      await controller.deleteVault('wrong');

      expect(await guard.failureCount(), greaterThan(before));
    });
  });

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

  group('reading and deleting a file in the open environment', () {
    test('readFile returns the bytes that were stored', () async {
      final controller = buildController();
      addTearDown(controller.dispose);
      final store = VaultStore(tempDir, sodium);

      await controller.createVault('correct horse battery staple');
      final slots = await store.readSlots();
      final dataKey =
          tryUnlockFor(sodium, 'correct horse battery staple', slots);
      final entry =
          await store.put(dataKey, 0, 'note.txt', _bytes([7, 8, 9]));
      controller.lock();
      await controller.unlock('correct horse battery staple');

      expect(await controller.readFile(entry.id), equals(_bytes([7, 8, 9])));
    });

    test('readFile returns null while the vault is locked', () async {
      final controller = buildController();
      addTearDown(controller.dispose);
      final store = VaultStore(tempDir, sodium);

      await controller.createVault('correct horse battery staple');
      final slots = await store.readSlots();
      final dataKey =
          tryUnlockFor(sodium, 'correct horse battery staple', slots);
      final entry =
          await store.put(dataKey, 0, 'note.txt', _bytes([7, 8, 9]));
      controller.lock();

      expect(await controller.readFile(entry.id), isNull,
          reason: 'a locked vault must not hand out plaintext');
    });

    test('deleteFile removes it from the list', () async {
      final controller = buildController();
      addTearDown(controller.dispose);
      final store = VaultStore(tempDir, sodium);

      await controller.createVault('correct horse battery staple');
      final slots = await store.readSlots();
      final dataKey =
          tryUnlockFor(sodium, 'correct horse battery staple', slots);
      final entry = await store.put(dataKey, 0, 'gone.txt', _bytes([1]));
      controller.lock();
      await controller.unlock('correct horse battery staple');
      expect(controller.state.entries, hasLength(1));

      expect(await controller.deleteFile(entry.id), isTrue);
      expect(controller.state.entries, isEmpty);
    });

    test('deleting in the decoy leaves the real environment untouched',
        () async {
      final controller = buildController();
      addTearDown(controller.dispose);
      final store = VaultStore(tempDir, sodium);

      await controller.createVault('correct horse battery staple');
      await controller.addDecoy('decoy passphrase entirely different');

      final slots = await store.readSlots();
      final realKey =
          tryUnlockFor(sodium, 'correct horse battery staple', slots);
      final decoyKey =
          tryUnlockFor(sodium, 'decoy passphrase entirely different', slots);
      await store.put(realKey, 0, 'real.txt', _bytes([1]));
      final decoyEntry =
          await store.put(decoyKey, 1, 'decoy.txt', _bytes([2]));

      controller.lock();
      await controller.unlock('decoy passphrase entirely different');
      await controller.deleteFile(decoyEntry.id);

      controller.lock();
      await controller.unlock('correct horse battery staple');
      expect(controller.state.entries, hasLength(1),
          reason: 'the two environments must not be able to affect, or '
              'reveal anything about, each other');
      expect(controller.state.entries.single.name, 'real.txt');
    });
  });

  group('a decoy cannot reuse the real passphrase', () {
    test('addDecoy refuses a passphrase that already opens another slot',
        () async {
      // Reported from device testing. tryUnlock takes the FIRST slot that
      // matches, so a decoy sharing the real passphrase can never be
      // opened: slot 0 always wins, the decoy's files are orphaned, and
      // the user believes they have a decoy they do not have. The design
      // calls an unconvincing decoy worse than none; an unreachable one
      // is worse still.
      final controller = buildController();
      addTearDown(controller.dispose);
      final store = VaultStore(tempDir, sodium);

      await controller.createVault('correct horse battery staple');
      await controller.addDecoy('correct horse battery staple');

      expect(controller.state.error, isNotNull,
          reason: 'the user must be told, not left with a silent no-op');

      // No half-made decoy left behind. An empty slot holds random filler
      // rather than null — that is deliberate, so disk inspection cannot
      // tell whether a decoy exists — so the check is that nothing opens
      // it, not that it is empty.
      final slots = await store.readSlots();
      final asDecoy = unwrapDataKey(
          sodium, 'correct horse battery staple', slots[1]!);
      expect(asDecoy, isNull,
          reason: 'the refused passphrase must not have been written');
    });

    test('a different decoy passphrase is still accepted', () async {
      final controller = buildController();
      addTearDown(controller.dispose);
      final store = VaultStore(tempDir, sodium);

      await controller.createVault('correct horse battery staple');
      await controller.addDecoy('decoy passphrase entirely different');

      expect(controller.state.error, isNull);
      final slots = await store.readSlots();
      expect(slots[1], isNotNull);
    });

    test('both environments stay reachable after a valid decoy', () async {
      final controller = buildController();
      addTearDown(controller.dispose);

      await controller.createVault('correct horse battery staple');
      await controller.addDecoy('decoy passphrase entirely different');

      controller.lock();
      expect(await controller.unlock('correct horse battery staple'), isTrue);
      expect(controller.state.slot, 0);

      controller.lock();
      expect(
          await controller.unlock('decoy passphrase entirely different'), isTrue);
      expect(controller.state.slot, 1);
    });
  });
}
