/// The setup screen asks for both passphrases.
///
/// ADR 0002, part two. Part one made the controller provision both
/// environments and removed "Set up decoy" from Settings — which left
/// the setup screen asking for one passphrase and so creating a vault
/// with no decoy and no way to add one.
///
/// Two steps rather than two fields on one screen: each passphrase has
/// to be written down before the next is shown, and a screen offering
/// both at once invites copying one and skimming the other.
library;

import 'dart:io';

import 'package:dead_drop/ui/theme.dart';
import 'package:dead_drop/ui/vault/vault_controller.dart';
import 'package:dead_drop/ui/vault/vault_setup_page.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumSumo sodium;
  late Directory tempDir;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('setup_both_ui_');
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<ProviderContainer> pumpSetup(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: deadDropTheme(),
          home: const VaultSetupPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// The passphrase currently on screen.
  String shown(WidgetTester tester) => tester
      .widget<SelectableText>(find.byKey(const Key('generatedPassphrase')))
      .data!;

  testWidgets('the first step does not create the vault', (tester) async {
    final container = await pumpSetup(tester);

    expect(find.text('Create vault'), findsNothing,
        reason: 'the first step leads to the second, not to a vault '
            'with no decoy in it');

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(container.read(vaultControllerProvider).exists, isFalse,
        reason: 'nothing is written until both passphrases are chosen');
  });

  testWidgets('the second step offers a different passphrase',
      (tester) async {
    await pumpSetup(tester);
    final first = shown(tester);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(shown(tester), isNot(first),
        reason: 'two environments behind one passphrase are one '
            'environment');
  });

  testWidgets('completing both steps creates both environments',
      (tester) async {
    final container = await pumpSetup(tester);
    final real = shown(tester);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final decoy = shown(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    // The create button must actually be live, or the tap below does
    // nothing and the assertion that follows fails for the wrong
    // reason.
    final button =
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull,
        reason: 'the second step must be completable');

    // Pressed through runAsync: creating a vault derives two keys with
    // Argon2id, which is real work the pump guard will not run.
    await tester.runAsync(() async => button.onPressed!());
    await tester.pumpAndSettle();

    final controller = container.read(vaultControllerProvider.notifier);
    expect(controller.state.exists, isTrue,
        reason: 'controller error was: ${controller.state.error}');

    controller.lock();
    expect(await tester.runAsync(() => controller.unlock(real)), isTrue);
    expect(controller.state.slot, 0);

    controller.lock();
    expect(await tester.runAsync(() => controller.unlock(decoy)), isTrue);
    expect(controller.state.slot, 1,
        reason: 'the second passphrase must open the decoy');
  });
}
