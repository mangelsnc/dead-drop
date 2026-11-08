/// The window read-back is a diagnostic, and stays out of normal builds.
///
/// [readWindowState] exists to settle one question on one phone: when a
/// Redmi on HyperOS dims mid-transfer, has the keep-awake flag been
/// dropped or has the pinned brightness been reverted? Those have
/// different fixes. It is not something an ordinary build needs, so it
/// is gated the way the frame dumper is — a compile-time constant the
/// tree shaker can act on, rather than a flag someone has to remember.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/screen_wake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('this test binary has the diagnostics off', () {
    expect(wakeDiagnostics, isFalse);
  });

  test('the flag is a compile-time constant', () {
    // `const` is what lets the tree shaker drop readWindowState and its
    // callers. A `final` would behave identically here and ship them.
    final source = File('lib/src/screen_wake.dart').readAsStringSync();
    expect(
      source,
      contains('const bool wakeDiagnostics ='),
      reason: 'a `final` here would ship the diagnostic to users',
    );
    expect(
      source,
      contains("bool.fromEnvironment('DEADDROP_WAKE_DIAGNOSTICS')"),
    );
  });

  test('a call made anyway reaches no platform channel', () async {
    // The guard that matters: not that the flag is false, but that
    // calling it regardless touches nothing. This fails if someone
    // removes the `if (!wakeDiagnostics)` line.
    debugResetScreenWake();
    debugSupportedOverride = true;
    addTearDown(debugResetScreenWake);

    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.deaddrop/screen_wake'),
      (call) async {
        calls.add(call);
        return <String, Object?>{'keepScreenOn': true, 'brightness': 1.0};
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('dev.deaddrop/screen_wake'),
        null,
      );
    });

    expect(await readWindowState(), isNull);
    expect(calls, isEmpty,
        reason: 'a build without the flag asked the platform anyway');
  });

  test('the Android side answers the read-back', () {
    // The Dart half is useless if the native half never implements it:
    // the channel would return notImplemented and the diagnostic would
    // report "no answer" on exactly the device it was built for.
    final kotlin = File(
      'android/app/src/main/kotlin/dev/deaddrop/dead_drop/MainActivity.kt',
    ).readAsStringSync();

    expect(kotlin, contains('"readWindowState"'));
    expect(kotlin, contains('FLAG_KEEP_SCREEN_ON'),
        reason: 'it reports whether the flag is actually held');
    expect(kotlin, contains('screenBrightness'));
  });
}
