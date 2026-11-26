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

    // The unlock that served that wait is still in flight, and it has
    // to finish before this test returns: when it wakes it reads the
    // vault directory, which tearDown deletes. POSIX allows removing a
    // directory another handle still holds, so a pending unlock went
    // unnoticed here for as long as the test existed. Windows refuses,
    // and CI failed on Windows and nowhere else:
    //
    //   PathAccessException: Deletion failed … (OS Error: The process
    //   cannot access the file because it is being used by another
    //   process, errno = 32)
    //
    // Draining it needs both clocks. The controller's penalty is a
    // `Future.delayed` on the test clock, which only `pump` advances;
    // the slot read that follows it is real file I/O, which only
    // `runAsync` lets through. A fixed sleep does neither, which is why
    // the 100 ms one this replaces never drained anything.
    //
    // Waiting on the state the failed attempt lands, rather than on a
    // span of time, so the drain keeps working if the penalty curve
    // changes.
    await _settleUnlock(tester, container);

    expect(container.read(vaultControllerProvider).error,
        'Incorrect passphrase',
        reason: 'the attempt that served the wait is the one that then '
            'reports the wrong passphrase');
  });
}

/// Runs the in-flight unlock to completion, so nothing outlives the test.
///
/// Alternates the two clocks because the unlock spans both: `pump` moves
/// the test clock the penalty's `Future.delayed` is scheduled on, and
/// `runAsync` lets the real file I/O after it proceed. It stops as soon
/// as the attempt has reported, so it costs no more than the wait being
/// served.
Future<void> _settleUnlock(
  WidgetTester tester,
  ProviderContainer container,
) async {
  // Generous: enough to cover the penalty curve growing, short enough
  // that a genuinely stuck unlock fails the test rather than hanging CI.
  const limit = 60;
  for (var i = 0; i < limit; i++) {
    if (container.read(vaultControllerProvider).error != null) return;
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
  }
  fail('the penalised unlock never finished, so it would outlive the test '
      'and read the vault directory after tearDown deleted it — the '
      'failure Windows reports as errno 32');
}
