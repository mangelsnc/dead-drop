/// Forward secrecy: the per-transfer keys are never written anywhere.
///
/// docs/technical-spec.md states that "ephemeral X25519 keys are
/// generated per transfer and never stored", and the security document
/// offers forward secrecy on that basis: compromising a device later
/// must reveal nothing about transfers already finished. That property
/// is only worth the sentence if nothing persists the key.
///
/// It is also the reason a receiver has to re-scan after closing the
/// app, which reads as a defect and has been reported as one. Making
/// the key survive would be an easy "fix" that quietly withdraws the
/// guarantee — so the claim gets a test rather than a comment.
library;

import 'dart:io';

import 'package:dead_drop/src/crypto.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

/// Records every key the app asks the OS keychain to store.
class _RecordingSecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> data = {};
  final List<String> writes = [];

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    writes.add(key);
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

  test('generating a receiver keypair writes nothing to the keychain',
      () async {
    final storage = _RecordingSecureStorage();
    FlutterSecureStoragePlatform.instance = storage;

    final keypair = await ReceiverKeypair.generate(sodium);
    addTearDown(keypair.privateKey.dispose);

    expect(storage.writes, isEmpty,
        reason: 'an ephemeral key that reaches the keychain outlives its '
            'transfer, and forward secrecy goes with it');
  });

  test('two receivers in one run get different keys', () async {
    // The other half of "per transfer": a key reused across transfers
    // would also survive them, without ever being written down.
    final first = await ReceiverKeypair.generate(sodium);
    final second = await ReceiverKeypair.generate(sodium);
    addTearDown(first.privateKey.dispose);
    addTearDown(second.privateKey.dispose);

    expect(first.publicKey, isNot(equals(second.publicKey)));
  });

  test('no source file persists a receiver or ephemeral keypair', () {
    // The guard that survives a refactor. A later change that "fixes"
    // the re-scan by saving the keypair would pass both tests above if
    // it saved it somewhere other than the keychain — a file, a
    // preference — so the claim is also checked against the source.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (!source.contains('ReceiverKeypair')) continue;
      for (final marker in const [
        'writeAsBytes',
        'writeAsString',
        'SharedPreferences',
        'secureStorage.write',
      ]) {
        if (source.contains(marker)) {
          offenders.add('${entity.path}: $marker');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'a file handling ReceiverKeypair also writes to storage; '
            'check it is not the ephemeral key being persisted');
  });
}
