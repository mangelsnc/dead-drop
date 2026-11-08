/// A form column does not stretch across a maximised desktop window.
///
/// Reported from a maximised macOS window: the vault's Unlock button ran
/// about 1940 logical pixels wide and 48 tall. A control that shape is
/// hard to aim at and reads as a divider rather than a button, and a
/// text field that wide puts the caret a screen away from its label.
///
/// These screens are the ones a person meets while standing somewhere
/// they would rather not be, so the layout being obviously right matters
/// more here than on a settings page.
library;

import 'dart:io';

import 'package:dead_drop/ui/responsive.dart';
import 'package:dead_drop/ui/theme.dart';
import 'package:dead_drop/ui/vault/vault_controller.dart';
import 'package:dead_drop/ui/vault/vault_page.dart';
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
  late SodiumSumo sodium;
  late Directory tempDir;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('form_width_test_');
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// A maximised 27" window, which is where this was reported.
  Future<void> useWideWindow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2560, 1440);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('the unlock button does not span the whole window',
      (tester) async {
    await useWideWindow(tester);

    final container = ProviderContainer(overrides: [
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);

    final controller = container.read(vaultControllerProvider.notifier);
    await tester.runAsync(
        () => controller.createVault('correct horse battery staple six'));
    controller.lock();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: deadDropTheme(), home: const VaultPage()),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.getSize(find.byType(FilledButton));
    expect(button.width, lessThanOrEqualTo(kMaxFormWidth),
        reason: 'it was 1940px wide and 48 tall in a maximised window');
    expect(button.width / button.height, lessThan(15),
        reason: 'a control this wide and this short is not aimable');
  });

  testWidgets('the setup form does not span the whole window',
      (tester) async {
    // The screen before it has the same shape and the same defect.
    await useWideWindow(tester);

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

    expect(tester.getSize(find.byType(FilledButton)).width,
        lessThanOrEqualTo(kMaxFormWidth));
  });

  testWidgets('a phone-width window still fills its width', (tester) async {
    // The cap must not shrink the layout these screens were designed in.
    tester.view.physicalSize = const Size(390, 844);
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
        () => controller.createVault('correct horse battery staple six'));
    controller.lock();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: deadDropTheme(), home: const VaultPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 390 wide minus the 24pt padding on each side.
    expect(tester.getSize(find.byType(FilledButton)).width, 390 - 48,
        reason: 'a phone must not get a 480px column inside a 390px screen');
  });
}
