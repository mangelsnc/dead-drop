/// Creating a vault creates both of its environments.
///
/// ADR 0002. Provisioning the decoy separately left the app unable to
/// say whether one existed — it cannot, by design — so Settings offered
/// to "set up" a decoy that might already be there and overwrote it
/// without asking. Worse, the Security section rendered only for the
/// real environment, so an attacker who opened Settings under duress
/// learned from its absence that they were not in the real one.
///
/// Both environments now exist from creation, which removes the
/// question rather than answering it.
library;

import 'dart:io';
import 'dart:typed_data';

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
    tempDir = Directory.systemTemp.createTempSync('setup_both_test_');
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

  const real = 'correct horse battery staple six';
  const decoy = 'seven eight nine ten eleven twelve';

  test('both passphrases open their own environment', () async {
    final controller = build();
    await controller.createVault(real, decoyPassphrase: decoy);
    expect(controller.state.error, isNull);

    controller.lock();
    expect(await controller.unlock(real), isTrue);
    expect(controller.state.slot, 0);

    controller.lock();
    expect(await controller.unlock(decoy), isTrue);
    expect(controller.state.slot, 1,
        reason: 'the decoy must be its own environment, not the real one');
  });

  test('the two environments do not share files', () async {
    final controller = build();
    await controller.createVault(real, decoyPassphrase: decoy);

    await controller.saveFile('real.txt', Uint8List.fromList([1, 2, 3]));
    expect(controller.state.entries, hasLength(1));

    controller.lock();
    await controller.unlock(decoy);
    expect(controller.state.entries, isEmpty,
        reason: 'the decoy must not show what the real environment holds');
  });

  test('the same passphrase for both is refused', () async {
    // Two environments behind one passphrase are one environment:
    // tryUnlock returns the first slot that matches, so the decoy could
    // never be reached and its owner would believe they had a
    // protection they did not.
    final controller = build();
    await controller.createVault(real, decoyPassphrase: real);

    expect(controller.state.error, isNotNull);
    expect(controller.state.exists, isFalse,
        reason: 'a refused creation must not leave half a vault behind');
  });

  test('a vault made without a decoy still works', () async {
    // The parameter is optional, so existing callers and tests are
    // unaffected; what changes is what the setup screen passes.
    final controller = build();
    await controller.createVault(real);

    expect(controller.state.error, isNull);
    controller.lock();
    expect(await controller.unlock(real), isTrue);
  });
}
