/// Opening a screen must not mean a keychain prompt per widget.
///
/// On macOS, a build whose signature does not own a keychain item gets a
/// system dialog on every access to it. CI signs ad-hoc with a fresh
/// identity each run, so during development every access asks. Reported
/// from a real macOS build on 2026-11-05: two prompts on opening Send,
/// two more on starting a scan.
///
/// The signature is why a dialog appears at all, and a release build
/// signed with one identity will not show them. How *many* appear is this
/// store's business, and [IdentityStore] caches per instance — so what
/// matters is that one screen does not build several stores.
library;

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/identity_store.dart';

class _CountingStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> data = {};
  int reads = 0;

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async =>
      data[key] = value;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    reads++;
    return data[key];
  }

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
  Future<void> deleteAll({
    required Map<String, String> options,
  }) async =>
      data.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumSumo sodium;
  late _CountingStorage keychain;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    keychain = _CountingStorage();
    FlutterSecureStoragePlatform.instance = keychain;
  });

  test('one store serves many questions with one keychain read', () async {
    final store = IdentityStore(sodium);

    await store.loadOrGenerate();
    final before = keychain.reads;
    await store.fingerprint();
    await store.verifyKey();
    await store.fingerprint();

    expect(keychain.reads, before,
        reason: 'the identity is cached after the first load');
  });

  test('a second store reads the keychain again', () async {
    // What two widgets each resolving the provider costs, if the
    // provider ever hands out a second instance.
    await IdentityStore(sodium).fingerprint();
    final after = keychain.reads;
    await IdentityStore(sodium).fingerprint();

    expect(keychain.reads, greaterThan(after));
  });
}
