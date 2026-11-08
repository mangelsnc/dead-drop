/// Getting files into the vault, and the symmetry that must hold.
///
/// The decoy only works if it looks like somewhere a person keeps
/// things, which means it has to be as easy to put files into as the
/// real environment. It also means the two screens must offer exactly
/// the same controls: an "Add files" button in one and not the other
/// would say which environment is open, which is the disclosure the
/// whole feature set exists to prevent.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dead_drop/src/file_drop.dart';
import 'package:dead_drop/ui/theme.dart';
import 'package:dead_drop/ui/vault/add_files.dart';
import 'package:dead_drop/ui/vault/vault_controller.dart';
import 'package:dead_drop/ui/vault/vault_page.dart';
import 'package:flutter/material.dart';
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
  late SodiumSumo sodium;
  late Directory tempDir;

  const real = 'correct horse battery staple six';
  const decoy = 'seven eight nine ten eleven twelve';

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('add_files_test_');
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
  });

  tearDown(() {
    debugCanDropFilesOverride = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(overrides: [
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  /// Pumps the vault screen with [passphrase]'s environment open.
  Future<ProviderContainer> pumpOpen(
    WidgetTester tester,
    String passphrase,
  ) async {
    final container = makeContainer();
    final controller = container.read(vaultControllerProvider.notifier);
    await tester.runAsync(
        () => controller.createVault(real, decoyPassphrase: decoy));
    controller.lock();
    await tester.runAsync(() => controller.unlock(passphrase));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: deadDropTheme(), home: const VaultPage()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('the control is present in both environments', () {
    testWidgets('the real environment offers Add files', (tester) async {
      await pumpOpen(tester, real);
      expect(find.widgetWithText(FilledButton, 'Add files'), findsOneWidget);
    });

    testWidgets('the decoy offers exactly the same', (tester) async {
      // The property that matters. A decoy you cannot add to is a decoy
      // that goes stale, and a decoy missing a button the real vault has
      // is a decoy that identifies itself.
      await pumpOpen(tester, decoy);
      expect(find.widgetWithText(FilledButton, 'Add files'), findsOneWidget);
    });
  });

  group('sealing files', () {
    testWidgets('a file is sealed into whichever environment is open',
        (tester) async {
      final container = await pumpOpen(tester, decoy);
      final ref = container.read(vaultControllerProvider.notifier);

      await tester.runAsync(() async {
        await ref.saveFile('note.txt', Uint8List.fromList([1, 2, 3]));
      });
      await tester.pumpAndSettle();

      expect(container.read(vaultControllerProvider).entries.single.name,
          'note.txt');

      // And it did not land in the other environment.
      ref.lock();
      await tester.runAsync(() => ref.unlock(real));
      expect(container.read(vaultControllerProvider).entries, isEmpty,
          reason: 'a file added to the decoy must not appear in the real '
              'environment');
    });

    testWidgets('an unreadable file does not discard the rest',
        (tester) async {
      final container = await pumpOpen(tester, real);
      late String? message;

      await tester.runAsync(() async {
        message = await addFilesToVault(
          _RefShim(container),
          [
            (name: 'good.txt', read: () async => Uint8List.fromList([1])),
            (name: 'bad.txt', read: () async => throw const FileSystemException('nope')),
            (name: 'also-good.txt', read: () async => Uint8List.fromList([2])),
          ],
        );
      });
      await tester.pumpAndSettle();

      expect(container.read(vaultControllerProvider).entries.length, 2,
          reason: 'one bad file in a dragged batch must not lose the others');
      expect(message, contains('bad.txt'));
    });

    testWidgets('a file over the size cap is refused by name',
        (tester) async {
      final container = await pumpOpen(tester, real);
      late String? message;

      await tester.runAsync(() async {
        message = await addFilesToVault(
          _RefShim(container),
          [
            (
              name: 'huge.bin',
              read: () async => Uint8List(kMaxVaultFileBytes + 1),
            ),
          ],
        );
      });
      await tester.pumpAndSettle();

      expect(container.read(vaultControllerProvider).entries, isEmpty);
      expect(message, contains('huge.bin'));
    });
  });

  group('the drop target', () {
    testWidgets('is a pass-through where files cannot be dragged',
        (tester) async {
      // A phone has nothing to drag from, so the wrapper must not add a
      // layer or change what the screen looks like.
      debugCanDropFilesOverride = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: deadDropTheme(),
          home: VaultDropTarget(
            onResult: (_) {},
            child: const Text('inner'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('inner'), findsOneWidget);
      expect(find.byType(Stack), findsNothing,
          reason: 'no overlay machinery on a platform that cannot drop');
    });
  });
}

/// Minimal WidgetRef over a container, so addFilesToVault can be driven
/// directly rather than through a file picker the test cannot open.
class _RefShim implements WidgetRef {
  _RefShim(this._container);
  final ProviderContainer _container;

  @override
  T read<T>(ProviderListenable<T> provider) => _container.read(provider);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not needed by these tests');
}
