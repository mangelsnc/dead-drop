/// Adding a decoy must refuse only a passphrase that really opens
/// something.
///
/// Reported on 2026-11-07: a Mac with a vault already created, adding a
/// decoy with a passphrase the owner says is different, refused with
/// "that passphrase already opens an environment". If that refusal can
/// fire against a passphrase that opens nothing, the decoy — the whole
/// coercion defence — cannot be created at all.
library;

import 'dart:io';

import 'package:dead_drop/ui/vault/vault_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

class _FakeSecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> data = {};

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
  late Directory tempDir;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('add_decoy_test_');
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  VaultController build() {
    final container = ProviderContainer(overrides: [
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);
    return container.read(vaultControllerProvider.notifier);
  }

  test('a genuinely different decoy passphrase is accepted', () async {
    final controller = build();
    await controller.createVault('correct horse battery staple six');

    await controller.addDecoy('seven eight nine ten eleven twelve');

    expect(controller.state.error, isNull,
        reason: 'a passphrase that opens nothing must not be refused');
  });

  test('the refusal fires only for a passphrase that does open one',
      () async {
    final controller = build();
    await controller.createVault('correct horse battery staple six');

    await controller.addDecoy('correct horse battery staple six');

    expect(controller.state.error, isNotNull);
    expect(controller.state.error, contains('already opens'));
  });

  test('a decoy can be added while the vault is locked', () async {
    // The owner's path: create a vault, lock it, come back later and add
    // a decoy. Nothing here should depend on an environment being open.
    final controller = build();
    await controller.createVault('correct horse battery staple six');
    controller.lock();

    await controller.addDecoy('seven eight nine ten eleven twelve');

    expect(controller.state.error, isNull);
  });

  test('a decoy can be replaced with a new passphrase', () async {
    // The case the report most resembles: a decoy already exists, and
    // the owner adds another with a third passphrase.
    final controller = build();
    await controller.createVault('correct horse battery staple six');
    await controller.addDecoy('seven eight nine ten eleven twelve');

    await controller.addDecoy('thirteen fourteen fifteen sixteen seventeen');

    expect(controller.state.error, isNull,
        reason: 'a third, unused passphrase opens nothing');
  });

  test('both environments still open after a decoy is replaced', () async {
    final controller = build();
    const real = 'correct horse battery staple six';
    const second = 'thirteen fourteen fifteen sixteen seventeen';
    await controller.createVault(real);
    await controller.addDecoy('seven eight nine ten eleven twelve');
    await controller.addDecoy(second);
    controller.lock();

    expect(await controller.unlock(real), isTrue, reason: 'the real one');
    controller.lock();
    expect(await controller.unlock(second), isTrue, reason: 'the new decoy');
  });
}
