/// Tests for the receive flow's second save destination: the vault
/// (app/lib/ui/receive/receive_page.dart's `saveToVault`/`_saveToVault`,
/// app/lib/ui/vault/vault_controller.dart's `saveFile`).
///
/// Three properties matter here:
///
/// - The vault destination is **absent**, not disabled, until a vault
///   exists in this session — an attacker must not learn the feature exists
///   from a greyed-out button (see home_page.dart's identical treatment of
///   its own Vault entry).
/// - Once a vault exists, both destinations are offered.
/// - Saving to the vault must never write plaintext to disk at any point —
///   not a temp file, not a file-picker path, nothing. This is checked by
///   actually walking the filesystem under the vault's root and the OS temp
///   directory looking for the plaintext bytes, not by asserting that some
///   method was never called.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/main.dart';
import 'package:dead_drop/src/crypto.dart';
import 'package:dead_drop/src/receiver.dart';
import 'package:dead_drop/src/tofu_store.dart';
import 'package:dead_drop/src/vault/vault_store.dart';
import 'package:dead_drop/ui/receive/receive_page.dart';
import 'package:dead_drop/ui/theme.dart';
import 'package:dead_drop/ui/vault/vault_controller.dart';

/// In-memory fake for [FlutterSecureStoragePlatform] — identical in spirit
/// to provider_scoping_test.dart's: `flutter_secure_storage` talks to the OS
/// keychain over a platform channel that doesn't exist in the
/// `flutter_tester` VM. [TofuStore] (watched indirectly via
/// `tofuStoreProvider`, which `receiveProvider` depends on) needs a fake
/// backing store to construct at all under `flutter test`.
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

/// A [ReceiveNotifier] seeded directly into a completed-transfer state,
/// bypassing the real QR/handshake pipeline — these tests are about which
/// save destinations the result card offers, not about the transfer itself.
///
/// The result card only renders once `ReceiveState.sessionActive`
/// (`receiver != null`) is true (see receive_page.dart), so a bare
/// `Receiver` with no session/decoder is constructed here purely to satisfy
/// that gate — these tests never drive it through an actual handshake.
class _CompletedReceiveNotifier extends ReceiveNotifier {
  _CompletedReceiveNotifier(SodiumSumo sodium, TofuStore tofuStore)
      : super(sodium, tofuStore) {
    _seed(sodium);
  }

  Future<void> _seed(SodiumSumo sodium) async {
    final keypair = await ReceiverKeypair.generate(sodium);
    state = state.copyWith(
      receiver: Receiver(sodium: sodium, keypair: keypair),
      fileBytes: Uint8List.fromList(utf8.encode('received file contents')),
      fileName: 'report.pdf',
      totalChunks: 1,
      chunksDecoded: 1,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumSumo sodium;
  late Directory tempDir;
  late _FakeSecureStorage fakeStorage;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('receive_to_vault_test_');
    fakeStorage = _FakeSecureStorage();
    FlutterSecureStoragePlatform.instance = fakeStorage;
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget wrap(Widget child, {required Directory vaultDir}) {
    return ProviderScope(
      overrides: [
        sodiumProvider.overrideWithValue(sodium),
        sodiumSumoProvider.overrideWithValue(sodium),
        vaultDirectoryProvider.overrideWithValue(vaultDir),
        receiveProvider.overrideWith(
          (ref) => _CompletedReceiveNotifier(
            sodium,
            ref.watch(tofuStoreProvider),
          ),
        ),
      ],
      child: MaterialApp(
        theme: deadDropTheme(),
        home: child,
      ),
    );
  }

  testWidgets('with no vault, only Save to device is offered', (tester) async {
    await tester.pumpWidget(wrap(const ReceivePage(), vaultDir: tempDir));
    await tester.pumpAndSettle();

    expect(find.text('Device'), findsOneWidget);
    expect(find.text('Vault'), findsNothing);
  });

  testWidgets('with a vault, both destinations are offered', (tester) async {
    final container = ProviderContainer(overrides: [
      sodiumProvider.overrideWithValue(sodium),
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
      receiveProvider.overrideWith(
        (ref) => _CompletedReceiveNotifier(
          sodium,
          ref.watch(tofuStoreProvider),
        ),
      ),
    ]);
    addTearDown(container.dispose);

    // Real disk I/O (VaultStore.init/writeSlots uses flush:true writes) must
    // run via tester.runAsync, outside flutter_test's fake-async zone — see
    // vault_ui_test.dart for why.
    await tester.runAsync(() async {
      await container
          .read(vaultControllerProvider.notifier)
          .createVault('correct horse battery staple');
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: deadDropTheme(), home: const ReceivePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Device'), findsOneWidget);
    expect(find.text('Vault'), findsOneWidget);
  });

  test('saving to the vault writes no plaintext to disk', () async {
    final storeDir = Directory('${tempDir.path}/store');
    final vaultStore = VaultStore(storeDir, sodium);
    final controller = VaultController(sodium, vaultStore);
    addTearDown(controller.dispose);

    await controller.createVault('correct horse battery staple');

    const secretMarker = 'DEADDROP-PLAINTEXT-MARKER-DO-NOT-LEAK';
    final bytes = Uint8List.fromList(utf8.encode(secretMarker));

    // Snapshot system temp before the save so the check below can look at
    // the files this save created, rather than at every file the machine
    // happens to have in /tmp.
    final tempBefore = <String>{
      for (final e in Directory.systemTemp.listSync()) e.path,
    };

    final entry = await controller.saveFile('secret.txt', bytes);
    expect(entry, isNotNull);

    // Walk every file actually written under the vault's store directory —
    // not a mock, not an assertion that some method was never invoked — and
    // confirm the plaintext marker never appears in any of them.
    final offenders = <String>[];
    await for (final e in storeDir.list(recursive: true)) {
      if (e is! File) continue;
      final raw = await e.readAsBytes();
      if (_containsBytes(raw, utf8.encode(secretMarker))) {
        offenders.add(e.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'plaintext marker leaked into: $offenders');

    // Also check for a scratch file written outside the vault's own root
    // (e.g. via a file picker, or a stray temp file) — the whole point of
    // saveFile() is that it never touches FilePicker or any path outside
    // the sealed store.
    //
    // Only entries that appeared during the save are examined. Reading
    // every file already in system temp made this test depend on unrelated
    // files on the host: on a CI runner, whose /tmp holds hundreds of
    // megabytes of other jobs' data, it timed out at 30s. It also could not
    // distinguish our leak from someone else's file.
    final sysTempOffenders = <String>[];
    for (final e in Directory.systemTemp.listSync()) {
      if (e is! File || tempBefore.contains(e.path)) continue;
      try {
        if (_containsBytes(e.readAsBytesSync(), utf8.encode(secretMarker))) {
          sysTempOffenders.add(e.path);
        }
      } on FileSystemException {
        // Appeared and vanished again mid-test — not ours to read.
      }
    }
    expect(sysTempOffenders, isEmpty,
        reason: 'plaintext marker leaked into system temp: $sysTempOffenders');
  });
}

bool _containsBytes(Uint8List haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) return false;
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}
