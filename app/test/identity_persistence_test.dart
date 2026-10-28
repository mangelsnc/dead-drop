/// The device identity must survive a restart.
///
/// Asked after device testing: "should a sender keep the same public key?
/// it looks like it changes every time." It should. The ephemeral X25519
/// key does change per transfer — that is forward secrecy — but the
/// Ed25519 identity behind the fingerprint is what correspondents check,
/// and it has to be the same tomorrow.
///
/// The failure these tests guard is silent: if the keychain rejects the
/// write, loadOrGenerate makes a fresh identity on every launch and
/// nothing says so. macOS did exactly that until 0.6.0.
library;

import 'package:dead_drop/src/identity_store.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

/// In-memory keychain. [writesSucceed] false models a platform that
/// accepts a write and stores nothing — the macOS failure.
class _FakeSecureStorage extends FlutterSecureStoragePlatform {
  _FakeSecureStorage({this.writesSucceed = true});

  final bool writesSucceed;
  final Map<String, String> data = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (writesSucceed) data[key] = value;
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
  }) async =>
      data.remove(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(data);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      data.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumSumo sodium;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  test('the same identity comes back on the next launch', () async {
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();

    final first = await IdentityStore(sodium).loadOrGenerate();
    // A second store is a second launch: same storage, no cache.
    final second = await IdentityStore(sodium).loadOrGenerate();

    expect(second.fingerprint, first.fingerprint,
        reason: 'a correspondent who verified this device once must not '
            'have to verify it again tomorrow');
  });

  test('a storage that silently drops writes is reported, not ignored',
      () async {
    FlutterSecureStoragePlatform.instance =
        _FakeSecureStorage(writesSucceed: false);

    await expectLater(
      IdentityStore(sodium).loadOrGenerate(),
      throwsA(isA<IdentityNotPersistedException>()),
      reason: 'otherwise every launch invents a new identity and nothing '
          'anywhere says why',
    );
  });

  test('isPersisted is true once the identity is stored', () async {
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();

    final store = IdentityStore(sodium);
    await store.loadOrGenerate();

    expect(await store.isPersisted(), isTrue);
  });

  test('two environments keep separate identities', () async {
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();

    final real = await IdentityStore(sodium).loadOrGenerate();
    final decoy =
        await IdentityStore(sodium, environmentSlot: 1).loadOrGenerate();

    expect(decoy.fingerprint, isNot(real.fingerprint),
        reason: 'an attacker inside the decoy must not see the real '
            'fingerprint');
  });
}
