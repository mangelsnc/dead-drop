/// The receive screen must keep the display awake for as long as it is
/// open, not only while the camera runs.
///
/// Reported from a real Android device: the screen kept dimming. The
/// wakelock was taken in startScanning and released in stopScanning, which
/// leaves the handshake QR — shown first, then stared at by the other
/// person while they line their camera up — entirely uncovered. A phone
/// that dims during that wait hides the thing the sender is trying to read.
library;

import 'package:dead_drop/main.dart';
import 'package:dead_drop/src/screen_wake.dart';
import 'package:dead_drop/ui/receive/receive_page.dart';
import 'package:dead_drop/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

/// `flutter_secure_storage` talks to the OS keychain over a platform
/// channel that does not exist in the `flutter_tester` VM, and TofuStore —
/// reached through receiveProvider — needs it to construct at all.
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

  /// What the native side was asked to do, in order.
  late List<String> calls;

  setUpAll(() async {
    sodium = await SodiumSumoInit.init();
  });

  setUp(() {
    calls = [];
    debugResetScreenWake();
    // Tests run on the host, where Platform.isAndroid is false and the
    // wakelock is a deliberate no-op. Pretend to be a phone so the
    // lifecycle this file exists to pin is actually exercised.
    debugSupportedOverride = true;
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.deaddrop/screen_wake'),
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.deaddrop/screen_wake'),
      null,
    );
    debugResetScreenWake();
  });

  Widget wrap(Widget home) => ProviderScope(
        overrides: [
          sodiumProvider.overrideWithValue(sodium),
        ],
        child: MaterialApp(theme: deadDropTheme(), home: home),
      );

  testWidgets('opening the receive screen asks to keep the screen awake',
      (tester) async {
    await tester.pumpWidget(wrap(const ReceivePage()));
    await tester.pump();

    expect(calls, contains('keepAwake'),
        reason: 'the handshake QR is on display from the moment the screen '
            'opens, before any camera starts');
  });

  testWidgets('leaving the receive screen lets the screen sleep again',
      (tester) async {
    await tester.pumpWidget(wrap(const ReceivePage()));
    await tester.pump();
    calls.clear();

    // Replace the page: its State is disposed, as when the user goes back.
    await tester.pumpWidget(wrap(const Scaffold(body: SizedBox())));
    await tester.pump();

    expect(calls, contains('allowSleep'),
        reason: 'a wakelock left held drains a battery its owner may have '
            'no way to charge');
  });
}
