/// Tests for the vault session controller
/// (app/lib/ui/vault/vault_controller.dart).
///
/// This is the integration point between the crypto/storage layers and the
/// UI: it owns the open environment's data key and the decrypted entry
/// list, and is responsible for making both disappear the moment the vault
/// should no longer be considered open — whether that's an explicit
/// `lock()` or the app being backgrounded (Review Focus #2).
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/vault/vault_session.dart';
import 'package:dead_drop/src/vault/vault_store.dart';
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

/// Loads the native libsodium library for the current test platform.
///
/// `flutter test` runs in the flutter_tester VM, which does NOT link the
/// libsodium binaries bundled by sodium_libs (that only happens in real app
/// builds). So in tests we must load the library manually. We prefer the
/// binaries bundled in the sodium_libs package (pub cache) and fall back to
/// system-wide installations. See:
/// https://github.com/Skycoder42/libsodium_dart_bindings/issues/23
DynamicLibrary _loadLibsodium() {
  for (final candidate in _libsodiumCandidates()) {
    try {
      return DynamicLibrary.open(candidate);
    } on ArgumentError {
      // Not found / not loadable — try next candidate.
    }
  }
  throw StateError(
    'Could not load libsodium on ${Platform.operatingSystem}. '
    'Tried: ${_libsodiumCandidates().join(', ')}',
  );
}

/// Candidate paths/names for the native libsodium library, in order.
List<String> _libsodiumCandidates() {
  final bundled = _bundledSodiumLibsBinary();

  if (Platform.isLinux) {
    return [
      if (bundled != null) bundled,
      'libsodium.so.23',
      'libsodium.so',
    ];
  }
  if (Platform.isWindows) {
    return [
      if (bundled != null) bundled,
      'libsodium.dll',
    ];
  }
  if (Platform.isMacOS) {
    return [
      if (bundled != null) bundled,
      '/opt/homebrew/lib/libsodium.dylib',
      '/usr/local/lib/libsodium.dylib',
      'libsodium.dylib',
    ];
  }
  throw UnsupportedError(
      'Unsupported test platform: ${Platform.operatingSystem}');
}

/// Locates the libsodium binary bundled inside the sodium_libs package in
/// the pub cache, without hardcoding the package version.
String? _bundledSodiumLibsBinary() {
  final pubCache = Platform.environment['PUB_CACHE'];
  if (pubCache == null) return null;

  final hostedDir = Directory('$pubCache/hosted/pub.dev');
  if (!hostedDir.existsSync()) return null;

  Directory? pkgDir;
  for (final entry in hostedDir.listSync()) {
    if (entry is Directory && entry.path.contains('sodium_libs-')) {
      pkgDir = entry;
      break;
    }
  }
  if (pkgDir == null) return null;

  final relPath = Platform.isLinux
      ? 'linux/lib/x86_64/libsodium.so'
      : Platform.isWindows
          ? 'windows/lib/Release/v143/libsodium.dll'
          : Platform.isMacOS
              ? 'macos/Libraries/libsodium.dylib'
              : null;
  if (relPath == null) return null;

  final binary = File('${pkgDir.path}/$relPath');
  return binary.existsSync() ? binary.path : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumSumo sodium;
  late Directory tempDir;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init2(_loadLibsodium);
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('vault_controller_test_');
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

    controller.didChangeAppLifecycleState(AppLifecycleState.paused);

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
}
