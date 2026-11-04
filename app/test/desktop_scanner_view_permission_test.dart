/// A person who declined the camera has to be given a way back.
///
/// The owner did exactly that on 2026-11-04 — clicked the wrong button on
/// the macOS prompt — and the app became unusable with no explanation and
/// nothing to press. macOS never asks a second time, so the app cannot
/// simply retry: the only honest help is to say where the switch is and,
/// where the platform has one page to open, open it.
///
/// These tests drive the view with a camera that refuses, and check what
/// the person is shown.
library;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:dead_drop/src/desktop_camera.dart';
import 'package:dead_drop/ui/desktop_scanner_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A camera platform that refuses the way macOS refuses.
class _DenyingCameraPlatform extends CameraPlatform {
  _DenyingCameraPlatform(this.code, {this.message = 'access denied'});
  final String code;

  /// Separate from the code, because the timeout case has to carry a
  /// message that says nothing about permissions — otherwise the test
  /// supplies the very word it claims the app should not react to, and
  /// passes or fails for the wrong reason.
  final String message;

  @override
  Future<List<CameraDescription>> availableCameras() async =>
      throw PlatformException(code: code, message: message);
}

/// A camera platform that fails for a reason the user cannot fix in a
/// settings panel.
class _EmptyCameraPlatform extends CameraPlatform {
  @override
  Future<List<CameraDescription>> availableCameras() async => const [];
}

Future<void> _pump(
  WidgetTester tester, {
  required CameraPlatform platform,
  required String onPlatform,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DesktopScannerView(
          onDetect: (_) {},
          scanner: DesktopCameraScanner(platform: platform),
          platformOverride: onPlatform,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a declined camera on macOS offers the settings page',
      (tester) async {
    await _pump(
      tester,
      platform: _DenyingCameraPlatform('CameraAccessDenied'),
      onPlatform: 'macos',
    );

    expect(find.text('DeadDrop cannot use the camera'), findsOneWidget);
    expect(find.text('Open camera settings'), findsOneWidget);
    // The fact that explains why there is no "try again" button.
    expect(
      find.textContaining('will not ask again'),
      findsOneWidget,
    );
    // And the path, in the words on their own screen.
    expect(find.textContaining('Privacy & Security'), findsOneWidget);
  });

  testWidgets('Linux is told what to check instead of being given a button',
      (tester) async {
    // There is no single page to open on Linux, and a button that opens
    // nothing is worse than no button.
    await _pump(
      tester,
      platform: _DenyingCameraPlatform('CameraAccessDenied'),
      onPlatform: 'linux',
    );

    expect(find.text('DeadDrop cannot use the camera'), findsOneWidget);
    expect(find.text('Open camera settings'), findsNothing);
    expect(find.textContaining('camera device'), findsOneWidget);
  });

  testWidgets('a missing camera is not dressed up as a permission problem',
      (tester) async {
    // Sending someone to a settings panel over an unplugged webcam wastes
    // their time and teaches them the app's advice is noise.
    await _pump(
      tester,
      platform: _EmptyCameraPlatform(),
      onPlatform: 'macos',
    );

    expect(find.text('Open camera settings'), findsNothing);
    expect(find.text('DeadDrop cannot use the camera'), findsNothing);
    expect(find.textContaining('No camera found'), findsOneWidget);
  });

  testWidgets('the initialisation timeout keeps its own message',
      (tester) async {
    // The error a DeadDrop user is most likely to meet — it is what a busy
    // UI isolate produced before 55d06ff. Calling it a permission problem
    // would send them to a switch that is already on.
    await _pump(
      tester,
      platform: _DenyingCameraPlatform(
        'initialization_timeout',
        message: 'Camera initialization timed out, no frames received',
      ),
      onPlatform: 'macos',
    );

    expect(find.text('Open camera settings'), findsNothing);
    expect(find.text('DeadDrop cannot use the camera'), findsNothing);
  });
}
