/// One first contact must not mean a handful of keychain reads.
///
/// On macOS every keychain access by a binary that does not own the item
/// is a system dialog. A build signed ad-hoc by CI is a different binary
/// each time, so during development every single access asks — and a
/// receive screen that asked six times in a row was reported from a real
/// macOS build on 2026-11-05.
///
/// The signature is the reason the dialogs appear at all, and a release
/// build signed with one identity will not show them. How *many* appear
/// is this store's business: [TofuStore] caches what it loaded, so one
/// first contact should read the keychain once, however many questions
/// the receive flow asks of it.
library;

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/tofu_store.dart';

/// In-memory keychain that counts what the store asks of it.
class _CountingStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> data = {};
  int reads = 0;
  int writes = 0;

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    writes++;
    data[key] = value;
  }

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

const _sender = 'abcdef0123456789';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingStorage keychain;

  setUp(() {
    keychain = _CountingStorage();
    FlutterSecureStoragePlatform.instance = keychain;
  });

  test('one instance reads the keychain once across a first contact',
      () async {
    // The three questions the receive flow asks on an unknown sender:
    // isKnown when the bootstrap lands, then markKnown and nameFor once
    // the user accepts.
    final store = TofuStore();

    await store.isKnown(_sender);
    await store.markKnown(_sender, name: 'Redmi');
    await store.nameFor(_sender);

    expect(
      keychain.reads,
      1,
      reason: 'the store caches what it loaded; only the first call reads',
    );
  });

  test('a new instance per call reads the keychain every time', () async {
    // What a provider handing out a fresh store on each resolution costs.
    // This is the shape that produces a dialog per question on macOS.
    await TofuStore().isKnown(_sender);
    await TofuStore().markKnown(_sender, name: 'Redmi');
    await TofuStore().nameFor(_sender);

    expect(keychain.reads, greaterThan(1));
  });
}
