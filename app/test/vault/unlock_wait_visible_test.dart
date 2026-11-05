/// The unlock wait is on screen while it is being served.
///
/// The companion to unlock_wait_message_test.dart, which pins the
/// words. This one renders the real vault page and checks the message
/// is there during the pause and gone after it — the thing that was
/// actually reported: a spinner, several seconds of nothing, and a
/// person concluding the app had hung.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import 'package:dead_drop/src/vault/attempt_guard.dart';
import 'package:dead_drop/ui/theme.dart';
import 'package:dead_drop/ui/vault/vault_controller.dart';
import 'package:dead_drop/ui/vault/vault_page.dart';

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
  late _FakeSecureStorage keychain;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('unlock_wait_test_');
    keychain = _FakeSecureStorage();
    FlutterSecureStoragePlatform.instance = keychain;
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('a penalised attempt says how long the wait is',
      (tester) async {
    final container = ProviderContainer(overrides: [
      sodiumSumoProvider.overrideWithValue(sodium),
      vaultDirectoryProvider.overrideWithValue(tempDir),
    ]);
    addTearDown(container.dispose);

    final controller = container.read(vaultControllerProvider.notifier);
    await tester.runAsync(() => controller.createVault('correct horse '
        'battery staple'));
    controller.lock();

    // Spend the free attempts, so the next one is penalised. Done
    // against the guard directly: driving the UI through three wrong
    // passphrases would work but tests the same path three times.
    final guard = AttemptGuard();
    for (var i = 0; i < kFreeAttempts; i++) {
      await tester.runAsync(guard.recordFailure);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: deadDropTheme(), home: const VaultPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'wrong');
    await tester.tap(find.text('Unlock'));
    // One frame: enough for the controller to report the wait it is
    // about to serve, not enough for the wait to pass.
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('Too many failed attempts'),
      findsOneWidget,
      reason: 'the pause has to say what it is, or it reads as a hang',
    );
    expect(find.textContaining('5 seconds'), findsOneWidget);

    // And it must not hint at what happens at the threshold.
    expect(find.textContaining(RegExp('destruct|erase|destroy',
        caseSensitive: false)), findsNothing);

    // Let the countdown run to its end in fake time, then confirm it
    // cleans up after itself: a periodic timer left running would
    // keep rebuilding this page for the life of the app.
    await tester.pump(const Duration(seconds: 6));
    expect(find.textContaining('Too many failed attempts'), findsNothing,
        reason: 'the message must go when the wait does');

    // Drain the controller's own delay so nothing outlives the test.
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 100)));
    await tester.pump();
  });
}
