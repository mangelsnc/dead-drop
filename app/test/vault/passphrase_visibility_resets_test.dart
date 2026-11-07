/// Revealing a passphrase is for this moment, not for every one after.
///
/// The reveal toggle exists because a six-word passphrase is not in
/// anyone's muscle memory and a typo in a masked field is invisible. The
/// user decides when showing it is safe — they can see the room, the app
/// cannot. That decision is about the room they are in *now*, so it must
/// not outlive the screen: coming back later with someone else present
/// and finding the field already readable is the app making a judgement
/// about a room it never saw.
library;

import 'dart:io';

import 'package:dead_drop/ui/passphrase_field.dart';
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
  /// Whether the field is currently masked.
  bool masked(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).obscureText;

  Future<void> pumpField(WidgetTester tester, {Key? key}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: deadDropTheme(),
        home: Scaffold(
          body: PassphraseField(
            key: key,
            controller: TextEditingController(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a passphrase field starts masked', (tester) async {
    await pumpField(tester);
    expect(masked(tester), isTrue);
  });

  testWidgets('revealing it shows the text', (tester) async {
    await pumpField(tester);
    await tester.tap(find.byTooltip('Show passphrase'));
    await tester.pump();
    expect(masked(tester), isFalse);
  });

  testWidgets('a new field is masked however the last one was left',
      (tester) async {
    // The reported worry: leave it revealed, come back, and find every
    // passphrase readable as it is typed.
    await pumpField(tester, key: const ValueKey('first'));
    await tester.tap(find.byTooltip('Show passphrase'));
    await tester.pump();
    expect(masked(tester), isFalse);

    // A different field, as a different screen would build.
    await pumpField(tester, key: const ValueKey('second'));

    expect(masked(tester), isTrue,
        reason: 'the choice to reveal belongs to the moment it was made');
  });

  group('on the real vault screen', () {
    late SodiumSumo sodium;
    late Directory tempDir;

    setUpAll(() async {
      sodium = await SodiumSumoInit.init();
    });

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pass_vis_test_');
      FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    testWidgets('locking again does not bring back a revealed field',
        (tester) async {
      // The reported case: reveal the passphrase once, and every later
      // unlock shows what is typed. The unlock view is rebuilt rather
      // than recreated when the vault locks, so a reveal that lives in
      // its State would survive the round trip.
      const phrase = 'correct horse battery staple six';
      final container = ProviderContainer(overrides: [
        sodiumSumoProvider.overrideWithValue(sodium),
        vaultDirectoryProvider.overrideWithValue(tempDir),
      ]);
      addTearDown(container.dispose);

      final controller = container.read(vaultControllerProvider.notifier);
      await tester.runAsync(() => controller.createVault(phrase));
      controller.lock();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: deadDropTheme(), home: const VaultPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(masked(tester), isTrue, reason: 'the unlock field starts masked');

      await tester.tap(find.byTooltip('Show passphrase'));
      await tester.pump();
      expect(masked(tester), isFalse);

      // Unlock, then lock again — the round trip a user makes. The
      // unlock itself goes through the controller: driving the button
      // would run Argon2id inside the pump guard, which never settles.
      await tester.runAsync(() => controller.unlock(phrase));
      await tester.pumpAndSettle();
      expect(find.byType(PassphraseField), findsNothing,
          reason: 'the vault should be open now');

      controller.lock();
      await tester.pumpAndSettle();

      expect(masked(tester), isTrue,
          reason: 'coming back to a locked vault must not inherit a '
              'reveal made in whatever room the user was in before');
    });
  });
}