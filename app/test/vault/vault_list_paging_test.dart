/// Counting and paging the vault list.
///
/// Both are plain list affordances, and both must exist identically in
/// the real environment and the decoy: a count or a pager present in one
/// and missing from the other would answer the question the decoy is
/// there to leave open.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dead_drop/ui/theme.dart';
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
    tempDir = Directory.systemTemp.createTempSync('paging_test_');
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Opens [passphrase]'s environment holding [count] files.
  Future<ProviderContainer> pumpWithFiles(
    WidgetTester tester, {
    required String passphrase,
    required int count,
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(overrides: [
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);

    final controller = container.read(vaultControllerProvider.notifier);
    await tester.runAsync(
        () => controller.createVault(real, decoyPassphrase: decoy));
    controller.lock();
    await tester.runAsync(() => controller.unlock(passphrase));

    await tester.runAsync(() async {
      for (var i = 0; i < count; i++) {
        await controller.saveFile(
          'file-${i.toString().padLeft(3, '0')}.txt',
          Uint8List.fromList([i % 256]),
        );
      }
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: deadDropTheme(), home: const VaultPage()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('the total', () {
    testWidgets('one file reads in the singular', (tester) async {
      await pumpWithFiles(tester, passphrase: real, count: 1);
      expect(find.text('1 file'), findsOneWidget);
    });

    testWidgets('several files are counted', (tester) async {
      await pumpWithFiles(tester, passphrase: real, count: 4);
      expect(find.text('4 files'), findsOneWidget);
    });

    testWidgets('the decoy counts its own, and only its own',
        (tester) async {
      // The count must describe the environment that is open. Reporting
      // the real vault's total inside the decoy would be the leak.
      final container =
          await pumpWithFiles(tester, passphrase: real, count: 3);
      final controller = container.read(vaultControllerProvider.notifier);

      controller.lock();
      await tester.runAsync(() => controller.unlock(decoy));
      await tester.pumpAndSettle();

      expect(find.textContaining('3 files'), findsNothing,
          reason: 'the decoy must not report the count of the real '
              'environment');
    });
  });

  group('paging', () {
    testWidgets('one page of files shows no pager', (tester) async {
      await pumpWithFiles(tester, passphrase: real, count: 3);
      expect(find.byTooltip('Next page'), findsNothing,
          reason: 'a pager over three files is clutter');
    });

    testWidgets('past the page size the list is split', (tester) async {
      await pumpWithFiles(tester,
          passphrase: real, count: kVaultPageSize + 5);

      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('${kVaultPageSize + 5} files'), findsOneWidget,
          reason: 'the count is of everything, not of this page');

      // Newest first by default, so page one holds the highest numbers
      // and the oldest file is overleaf.
      expect(find.text('file-000.txt'), findsNothing);

      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('file-000.txt'), findsOneWidget);
    });

    testWidgets('the pager stops at both ends', (tester) async {
      await pumpWithFiles(tester,
          passphrase: real, count: kVaultPageSize + 1);

      // byTooltip finds the tooltip widget, not the button inside it.
      IconButton button(String tip) => tester.widget<IconButton>(
            find.ancestor(
              of: find.byTooltip(tip),
              matching: find.byType(IconButton),
            ),
          );

      expect(button('Previous page').onPressed, isNull,
          reason: 'there is nothing before the first page');
      expect(button('Next page').onPressed, isNotNull);

      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();

      expect(button('Next page').onPressed, isNull,
          reason: 'nor anything after the last');
      expect(button('Previous page').onPressed, isNotNull);
    });

    testWidgets('searching returns to the first page', (tester) async {
      // Deliberately a search whose results STILL span two pages. A
      // filter that collapses to one page is clamped back to page one
      // anyway, so it cannot tell a real reset from no reset at all --
      // the first version of this test passed with the reset deleted,
      // and a mutation probe caught it.
      await pumpWithFiles(tester,
          passphrase: real, count: kVaultPageSize * 3);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);

      // 'file-0' matches everything, so the page count does not shrink.
      await tester.enterText(find.byType(TextField).first, 'file-0');
      await tester.pumpAndSettle();

      expect(find.text('1 / 3'), findsOneWidget,
          reason: 'a new search starts at its first result, not at '
              'whatever page the last one was left on');
    });

    testWidgets('a search says how many of the whole it matched',
        (tester) async {
      await pumpWithFiles(tester, passphrase: real, count: 12);

      await tester.enterText(find.byType(TextField).first, 'file-01');
      await tester.pumpAndSettle();

      // file-010 and file-011.
      expect(find.text('2 of 12 files'), findsOneWidget);
    });
  });
}
