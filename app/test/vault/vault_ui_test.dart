/// Widget tests for the vault's UI: home screen entry, setup, and the
/// decoy's indistinguishability from the real environment
/// (app/lib/ui/vault/vault_page.dart, vault_setup_page.dart,
/// app/lib/ui/settings/settings_page.dart).
///
/// The third test here is the behavioural tell the whole feature rests on:
/// if the decoy's Settings screen shows even a greyed-out Security section,
/// an attacker learns the feature exists and keeps asking. Every other test
/// in this file matters; that one matters most.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/ui/home_page.dart';
import 'package:dead_drop/ui/theme.dart';
import 'package:dead_drop/ui/vault/vault_controller.dart';
import 'package:dead_drop/ui/vault/vault_page.dart';
import 'package:dead_drop/ui/vault/vault_setup_page.dart';
import 'package:dead_drop/ui/settings/settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumSumo sodium;
  late Directory tempDir;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('vault_ui_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget wrap(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: [
        sodiumSumoProvider.overrideWithValue(sodium),
        vaultDirectoryProvider.overrideWithValue(tempDir),
        ...overrides,
      ],
      child: MaterialApp(
        theme: deadDropTheme(),
        home: child,
      ),
    );
  }

  testWidgets('home shows no Vault entry before setup', (tester) async {
    await tester.pumpWidget(wrap(const HomePage()));
    await tester.pumpAndSettle();

    expect(find.text('Vault'), findsNothing);
  });

  testWidgets('home shows a Vault entry once a vault exists', (tester) async {
    final container = ProviderContainer(overrides: [
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);

    final controller = container.read(vaultControllerProvider.notifier);
    // Real disk I/O (VaultStore.init/writeSlots uses flush:true writes) must
    // run via tester.runAsync, outside flutter_test's fake-async zone —
    // otherwise the awaited Future never completes, because the fake clock
    // that zone uses never advances the real OS-level callback a flushed
    // write blocks on. Every createVault/addDecoy/unlock call below needs
    // the same treatment.
    await tester
        .runAsync(() => controller.createVault('correct horse battery staple'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: deadDropTheme(), home: const HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vault'), findsOneWidget);
  });

  testWidgets('the decoy environment shows no Security section in Settings',
      (tester) async {
    final container = ProviderContainer(overrides: [
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);

    final controller = container.read(vaultControllerProvider.notifier);
    await tester.runAsync(() async {
      await controller.createVault('correct horse battery staple');
      await controller.addDecoy('decoy passphrase entirely different');
      controller.lock();
      return controller.unlock('decoy passphrase entirely different');
    });
    expect(container.read(vaultControllerProvider).slot, equals(1));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: deadDropTheme(), home: const SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Not merely disabled/greyed out — entirely absent. A greyed-out
    // control would itself tell an attacker the feature exists.
    expect(find.text('Security'), findsNothing);
    expect(find.text('Self-destruct'), findsNothing);
  });

  testWidgets('the real environment shows a Security section in Settings',
      (tester) async {
    final container = ProviderContainer(overrides: [
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);

    final controller = container.read(vaultControllerProvider.notifier);
    await tester
        .runAsync(() => controller.createVault('correct horse battery staple'));
    expect(container.read(vaultControllerProvider).slot, equals(0));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: deadDropTheme(), home: const SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Security'), findsOneWidget);
  });

  testWidgets('deleting the vault is in Settings, not the vault app bar',
      (tester) async {
    // It used to sit one icon away from Settings in the vault's app
    // bar: an irreversible action in the position people press without
    // looking. Reported as precarious and failure-prone.
    final container = ProviderContainer(overrides: [
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);

    final controller = container.read(vaultControllerProvider.notifier);
    await tester
        .runAsync(() => controller.createVault('correct horse battery staple'));

    // The vault page offers Settings and nothing destructive beside it.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: deadDropTheme(), home: const VaultPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Delete vault'), findsNothing,
        reason: 'an irreversible action must not sit in the app bar '
            'beside the one people reach for without looking');
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    // It is reachable, under Security, where the other destructive
    // controls are.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: deadDropTheme(), home: const SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete vault'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
  });

  testWidgets('setup refuses a passphrase below the minimum', (tester) async {
    await tester.pumpWidget(wrap(const VaultSetupPage()));
    await tester.pumpAndSettle();

    // Switch to the secondary "type my own" path.
    await tester.tap(find.text('Type my own instead'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'password123');
    await tester.pumpAndSettle();

    expect(
        find.textContaining('too short').evaluate().isNotEmpty ||
            find.textContaining('predictable').evaluate().isNotEmpty ||
            find.textContaining('Weak').evaluate().isNotEmpty,
        isTrue);

    // The create/continue action must not proceed with a weak passphrase.
    final createButtonFinder =
        find.widgetWithText(FilledButton, 'Create vault');
    expect(createButtonFinder, findsOneWidget);
    final button = tester.widget<FilledButton>(createButtonFinder);
    expect(button.onPressed, isNull);
  });

  testWidgets('setup offers a generated passphrase', (tester) async {
    await tester.pumpWidget(wrap(const VaultSetupPage()));
    await tester.pumpAndSettle();

    // Generation is the default, leading path: a generated passphrase is
    // displayed up front, before any typing, with the secondary option
    // visible but not selected.
    expect(find.text('Type my own instead'), findsOneWidget);
    expect(find.textContaining('Copy'), findsOneWidget);

    // Six words, space separated — just check at least one bundled word is
    // present somewhere in the widget tree via a SelectableText/Text.
    final generatedTextFinder = find.byKey(const Key('generatedPassphrase'));
    expect(generatedTextFinder, findsOneWidget);
    final text = tester.widget<SelectableText>(generatedTextFinder).data!;
    expect(text.trim().split(' ').length, equals(6));
  });
}
