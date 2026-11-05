/// The sending screen holds the wakelock for as long as it is the medium.
///
/// A phone emitting animated QR codes is the thing the other device's
/// camera is reading. If its screen dims or locks the transfer stalls,
/// and the owner is holding the phone still rather than touching it, so
/// the system's idle timer has every reason to fire. Reported from a
/// Redmi Note 14 mid-transfer: the screen looked about to go out.
///
/// These pin the part that cannot be held in a hand to check: that the
/// request reaches the platform when emission starts, that nothing
/// between the two screens takes it away again, and that it is released
/// when the transfer ends.
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

  test('leaving the receive screen after the send screen took the lock '
      'does not release it', () async {
    // Both screens call into one process-global flag. On a phone used as
    // both ends in turn, the receive screen's dispose can run after the
    // send screen's acquire, because Flutter builds the incoming route
    // before disposing the outgoing one.
    await keepScreenAwake(); // receive screen opens
    await keepScreenAwake(brightness: 0.8); // send screen starts emitting
    await allowScreenSleep(); // receive screen disposes

    expect(
      isScreenAwakeHeld,
      isTrue,
      reason: 'the sender is still emitting and needs the screen on',
    );
  });

  test('the last screen to leave releases the lock', () async {
    // The counterpart: a count that never reaches zero would pin the
    // screen on for the rest of the app's life and drain a device whose
    // owner may have no way to charge it.
    await keepScreenAwake();
    await keepScreenAwake(brightness: 0.8);
    await allowScreenSleep();
    await allowScreenSleep();

    expect(isScreenAwakeHeld, isFalse);
    expect(calls.last.method, 'allowSleep');
  });

  test('a repeated acquire at the same level still has to be released',
      () async {
    // The idempotence guard skips the platform call when the level has
    // not changed. It must not also skip the claim, or the second
    // caller's release would free a lock the first one still wants.
    await keepScreenAwake(brightness: 0.5);
    await keepScreenAwake(brightness: 0.5);
    await allowScreenSleep();

    expect(isScreenAwakeHeld, isTrue);

    await allowScreenSleep();
    expect(isScreenAwakeHeld, isFalse);
  });

  test('a refused request still has to be released', () async {
    // The platform can say no. That caller will still release once, and
    // dropping their claim on failure would make that release free a
    // lock the other screen is holding.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.deaddrop/screen_wake'),
      (call) async {
        calls.add(call);
        if (calls.length == 2) {
          throw PlatformException(code: 'refused');
        }
        return null;
      },
    );

    await keepScreenAwake(); // receive screen: granted
    await keepScreenAwake(brightness: 0.8); // send screen: refused
    await allowScreenSleep(); // receive screen leaves

    expect(
      isScreenAwakeHeld,
      isTrue,
      reason: 'the refused caller has not released yet',
    );
  });

  test('an unbalanced release cannot drive the count negative', () async {
    // dispose can run on a screen that never acquired — the send screen
    // releases on stop, on reset and on dispose, which is three
    // releases for one acquire.
    await keepScreenAwake();
    await allowScreenSleep();
    await allowScreenSleep();
    await allowScreenSleep();

    expect(isScreenAwakeHeld, isFalse);

    // And the next transfer still gets the screen.
    await keepScreenAwake();
    expect(isScreenAwakeHeld, isTrue);
  });
}
