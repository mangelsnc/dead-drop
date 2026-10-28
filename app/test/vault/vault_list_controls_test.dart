/// Searching and ordering the vault's file list.
///
/// The controls work over the entries the controller has already
/// decrypted: nothing here reads the disk, so searching cannot reveal
/// anything about which environment is open. Both environments get the
/// same controls, because a search box present in one and absent in the
/// other would be exactly the tell the decoy exists to avoid.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/vault/vault_keys.dart';
import 'package:dead_drop/src/vault/vault_session.dart';
import 'package:dead_drop/src/vault/vault_store.dart';
import 'package:dead_drop/ui/theme.dart';
import 'package:dead_drop/ui/vault/vault_controller.dart';
import 'package:dead_drop/ui/vault/vault_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumSumo sodium;
  late Directory tempDir;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('vault_list_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Builds a vault holding three named files with distinct timestamps.
  Future<ProviderContainer> seeded(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);

    final controller = container.read(vaultControllerProvider.notifier);
    await tester.runAsync(() async {
      await controller.createVault('correct horse battery staple');
      final store = VaultStore(tempDir, sodium);
      final slots = await store.readSlots();
      final key = tryUnlock(sodium, 'correct horse battery staple',
              slots.cast<WrappedKey?>())
          .dataKey!;
      await store.put(key, 0, 'alpha.txt', Uint8List.fromList([1]));
      await store.put(key, 0, 'beta.png', Uint8List.fromList([2]));
      await store.put(key, 0, 'gamma.pdf', Uint8List.fromList([3]));
      controller.lock();
      return controller.unlock('correct horse battery staple');
    });
    return container;
  }

  Future<void> pump(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: deadDropTheme(), home: const VaultPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the search box filters the list as you type', (tester) async {
    final container = await seeded(tester);
    await pump(tester, container);

    expect(find.text('alpha.txt'), findsOneWidget);
    expect(find.text('beta.png'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pumpAndSettle();

    expect(find.text('beta.png'), findsOneWidget);
    expect(find.text('alpha.txt'), findsNothing,
        reason: 'a search that does not narrow the list is not a search');
  });

  testWidgets('a search matching nothing says so rather than looking empty',
      (tester) async {
    final container = await seeded(tester);
    await pump(tester, container);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing matches'), findsOneWidget,
        reason: 'an empty list and a vault with no files must not look '
            'the same');
  });

  testWidgets('sorting by name reorders the list', (tester) async {
    final container = await seeded(tester);
    await pump(tester, container);

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name A-Z').last);
    await tester.pumpAndSettle();

    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => s.contains('.'))
        .toList();
    final alpha = names.indexWhere((n) => n.startsWith('alpha'));
    final gamma = names.indexWhere((n) => n.startsWith('gamma'));
    expect(alpha, lessThan(gamma));
  });

  testWidgets('the controls appear in the decoy too', (tester) async {
    final container = ProviderContainer(overrides: [
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);

    final controller = container.read(vaultControllerProvider.notifier);
    await tester.runAsync(() async {
      await controller.createVault('correct horse battery staple');
      await controller.addDecoy('decoy passphrase entirely different');
      final store = VaultStore(tempDir, sodium);
      final slots = await store.readSlots();
      final key = tryUnlock(sodium, 'decoy passphrase entirely different',
              slots.cast<WrappedKey?>())
          .dataKey!;
      await store.put(key, 1, 'one.txt', Uint8List.fromList([1]));
      await store.put(key, 1, 'two.txt', Uint8List.fromList([2]));
      controller.lock();
      return controller.unlock('decoy passphrase entirely different');
    });

    await pump(tester, container);

    expect(find.byType(TextField), findsOneWidget,
        reason: 'controls in one environment and not the other would be '
            'a tell');
    expect(find.byIcon(Icons.sort), findsOneWidget);
  });
}
