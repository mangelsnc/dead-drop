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
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/ui/home_page.dart';
import 'package:dead_drop/ui/theme.dart';
import 'package:dead_drop/ui/vault/vault_controller.dart';
import 'package:dead_drop/ui/vault/vault_page.dart';
import 'package:dead_drop/ui/vault/vault_setup_page.dart';
import 'package:dead_drop/ui/settings/settings_page.dart';

/// In-memory keychain: the real plugin talks to the OS over a platform
/// channel that does not exist in flutter_tester, and the self-destruct
/// tile reads its preference from there.
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
    tempDir = Directory.systemTemp.createTempSync('vault_ui_test_');
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
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

  testWidgets('Settings looks the same in both environments', (tester) async {
    // ADR 0002. Settings used to render its Security section only for
    // slot 0, so an attacker who opened Settings in an environment
    // unlocked under duress and found no Security section learned they
    // were not in the real one. The design stopped the decoy from
    // revealing that a real environment exists and replaced it with the
    // real environment announcing that it is the real one.
    //
    // Both environments now render the same sections. Captured as text
    // rather than compared by eye: anything that differs between them
    // is a tell, whether or not anyone thought about it.
    final container = ProviderContainer(overrides: [
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);

    final controller = container.read(vaultControllerProvider.notifier);
    const real = 'correct horse battery staple';
    const decoy = 'decoy passphrase entirely different';
    await tester.runAsync(() async {
      await controller.createVault(real, decoyPassphrase: decoy);
    });

    Future<List<String>> settingsTextIn(String passphrase) async {
      await tester.runAsync(() async {
        controller.lock();
        return controller.unlock(passphrase);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: deadDropTheme(), home: const SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      // Settings is a ListView, so only what fits the viewport is
      // built. Scrolled to the end first, collecting as it goes:
      // comparing just the visible part would miss a tell below the
      // fold, which is where "Delete vault" sits.
      final seen = <String>{};
      void collect() => seen.addAll(tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((t) => t.isNotEmpty));
      collect();
      // Down to the end, then back to the top: a one-way sweep drops
      // whatever scrolled off before the last collect, which is not a
      // difference between environments but an artefact of how it was
      // read.
      for (var i = 0; i < 10; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pumpAndSettle();
        collect();
      }
      for (var i = 0; i < 10; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, 300));
        await tester.pumpAndSettle();
        collect();
      }
      return seen.toList()..sort();
    }

    final inReal = await settingsTextIn(real);
    expect(container.read(vaultControllerProvider).slot, 0);
    final inDecoy = await settingsTextIn(decoy);
    expect(container.read(vaultControllerProvider).slot, 1);

    final onlyInReal = inReal.toSet().difference(inDecoy.toSet());
    final onlyInDecoy = inDecoy.toSet().difference(inReal.toSet());
    expect({...onlyInReal, ...onlyInDecoy}, isEmpty,
        reason: 'anything Settings shows in one environment and not the '
            'other tells an attacker which one they are looking at.\n'
            'Only in the real environment: $onlyInReal\n'
            'Only in the decoy: $onlyInDecoy');
  });

  testWidgets('neither environment offers to set up a decoy', (tester) async {
    // It has one. Offering to "set up" a decoy both implied the user had
    // none — a claim the app cannot make, since an empty slot is
    // indistinguishable from a full one — and silently overwrote
    // whatever was there.
    final container = ProviderContainer(overrides: [
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);

    final controller = container.read(vaultControllerProvider.notifier);
    await tester.runAsync(() => controller.createVault(
          'correct horse battery staple',
          decoyPassphrase: 'decoy passphrase entirely different',
        ));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: deadDropTheme(), home: const SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('decoy', findRichText: true), findsNothing,
        reason: 'the decoy is not something to set up any more, and '
            'naming it here would be a tell of its own');
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

    expect(find.text('Security'), findsOneWidget);
    // Settings is a ListView: Delete vault sits below the fold on a
    // test-sized viewport and is not built until scrolled to.
    await tester.scrollUntilVisible(find.text('Delete vault'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Delete vault'), findsOneWidget);
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

    // The action must not proceed with a weak passphrase. On the first
    // step it reads "Continue" — setup provisions both environments
    // now (ADR 0002), so the first step leads to the second rather
    // than straight to a vault.
    final continueButton =
        find.widgetWithText(FilledButton, 'Continue');
    expect(continueButton, findsOneWidget);
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
  });

  testWidgets('the decoy step refuses a weak passphrase too', (tester) async {
    // The second passphrase is no less load-bearing than the first: a
    // decoy anyone can guess is a decoy that opens under pressure.
    await tester.pumpWidget(wrap(const VaultSetupPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    // The form column is capped at kMaxFormWidth, so in the 800x600
    // test window the content is taller than the viewport and these
    // controls have to be scrolled to before they can be used.
    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Type my own instead'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Type my own instead'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'password123');
    await tester.pumpAndSettle();

    final createButton = find.widgetWithText(FilledButton, 'Create vault');
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    expect(createButton, findsOneWidget);
    expect(tester.widget<FilledButton>(createButton).onPressed, isNull,
        reason: 'a weak decoy passphrase must not create the vault');
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
