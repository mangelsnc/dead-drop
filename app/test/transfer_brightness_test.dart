/// The sender's screen brightness travels to the platform.
///
/// The screen is the transmission medium, so how bright it is changes
/// what the other device's camera sees. Full brightness is right against
/// a phone camera and wrong against some webcams: a transfer from a
/// Redmi Note 14 to a Logitech StreamCam failed because the webcam's
/// auto-exposure metered the whole bright screen, stopped down, and the
/// code's dark modules came out grey.
///
/// These pin the parts a device cannot be held in hand to check: that a
/// chosen level reaches the platform channel rather than being dropped on
/// the way, that the default is unchanged from the behaviour before the
/// level was adjustable, and that a level outside the valid range cannot
/// reach the window.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/screen_wake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    debugResetScreenWake();
    // The host is not a phone, where this is a deliberate no-op.
    debugSupportedOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.deaddrop/screen_wake'),
      (call) async {
        calls.add(call);
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

  double? levelOf(MethodCall call) =>
      (call.arguments as Map?)?['level'] as double?;

  test('the default is full brightness', () async {
    // What the screen did before this was adjustable. A default that
    // quietly dimmed would make every existing transfer worse.
    await keepScreenAwake();

    expect(calls.single.method, 'keepAwake');
    expect(levelOf(calls.single), 1.0);
  });

  test('a chosen level reaches the platform', () async {
    await keepScreenAwake(brightness: 0.4);

    expect(levelOf(calls.single), closeTo(0.4, 0.0001));
  });

  test('a level outside the range is clamped before it is sent', () async {
    // A negative value is not a dim screen on Android: -1 is
    // BRIGHTNESS_OVERRIDE_NONE, which hands control back to the system
    // and would silently undo the setting.
    await keepScreenAwake(brightness: -3);
    expect(levelOf(calls.single), 0.0);

    await allowScreenSleep();
    calls.clear();

    await keepScreenAwake(brightness: 9);
    expect(levelOf(calls.single), 1.0);
  });

  test('a repeat while held does not re-apply', () async {
    // keepScreenAwake is called on every start; re-sending would fight a
    // level the user changed mid-transfer.
    await keepScreenAwake(brightness: 0.5);
    await keepScreenAwake(brightness: 0.9);

    expect(calls.length, 1);
    expect(levelOf(calls.single), closeTo(0.5, 0.0001));
  });

  test('releasing then re-acquiring applies the new level', () async {
    // The route a mid-transfer change takes: release, then ask again.
    await keepScreenAwake(brightness: 0.5);
    await allowScreenSleep();
    await keepScreenAwake(brightness: 0.9);

    expect(levelOf(calls.last), closeTo(0.9, 0.0001));
  });

  test('an unsupported platform sends nothing', () async {
    debugSupportedOverride = false;

    await keepScreenAwake(brightness: 0.5);

    expect(calls, isEmpty);
    expect(supportsTransferBrightness, isFalse,
        reason: 'the send screen hides the control when this is false');
  });
}
