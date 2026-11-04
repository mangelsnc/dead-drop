/// Can the app tell "you said no to the camera" from "the camera broke"?
///
/// The two need different words and different buttons. A failure the user
/// can fix by plugging something in should not send them to System
/// Settings, and a denied permission must not be dressed up as a hardware
/// fault — on macOS the system never asks twice, so a person who declined
/// by accident has no way back unless the app says where to go.
///
/// Reported by the owner on 2026-11-04: they denied the prompt by mistake,
/// the app became unusable, and they had to find the setting themselves.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/camera_permission.dart';

void main() {
  group('recognising a denied camera permission', () {
    test('the macOS permission errors are recognised', () {
      // The codes `camera_platform_interface` surfaces when TCC refuses.
      for (final code in [
        'CameraAccessDenied',
        'cameraAccessDenied',
        'AVFoundationErrorDomain',
      ]) {
        expect(isPermissionDenied(code), isTrue, reason: code);
      }
    });

    test('a message rather than a code is recognised too', () {
      // The plugin sometimes gives a sentence and no useful code, so the
      // text has to be read as well.
      expect(
        isPermissionDenied('Could not open the camera: access denied'),
        isTrue,
      );
      expect(
        isPermissionDenied('Camera access was not granted by the user'),
        isTrue,
      );
    });

    test('an ordinary camera failure is not mistaken for a refusal', () {
      // Sending someone to System Settings over a busy camera or an unplugged
      // webcam wastes their time and teaches them to ignore the advice.
      for (final message in [
        'No camera found. Connect one and try again.',
        'Another application may be using it.',
        'Could not list cameras: unknown error',
        'The camera stopped: stream closed',
      ]) {
        expect(isPermissionDenied(message), isFalse, reason: message);
      }
    });

    test('the initialisation timeout is not treated as a refusal', () {
      // This one is deliberate and was nearly got wrong. macOS reports
      // `initialization_timeout` when the UI isolate is too busy to let the
      // camera start — a bug fixed in 55d06ff — and it also appears when
      // the camera is genuinely slow. It is not a permission problem, and
      // claiming it is would send people to a setting that is already on.
      expect(
        isPermissionDenied(
          'CameraException(initialization_timeout, Camera initialization '
          'timed out, no frames received)',
        ),
        isFalse,
      );
    });

    test('a timeout wins even when the message also says denied', () {
      // The case that makes the guard load-bearing, and the one the
      // platform actually produces: macOS has reported a timeout whose
      // text mentions authorisation, because the camera it could not
      // start was one it would have had to ask about. Without the guard
      // the marker list matches and the app sends the user to a switch
      // that is already on — the single most confusing outcome available.
      //
      // Deleting the guard leaves every other test in this file passing,
      // so this is the one holding it.
      expect(
        isPermissionDenied(
          'initialization_timeout: no frames received (not authorized?)',
        ),
        isFalse,
      );
    });

    test('an empty or unknown failure is not a refusal', () {
      expect(isPermissionDenied(''), isFalse);
      expect(isPermissionDenied('something went wrong'), isFalse);
    });
  });

  group('what the app offers to do about it', () {
    test('only macOS and Windows can be sent to a settings page', () {
      // Linux has no single place to grant a camera: it is file permissions
      // on /dev/video*, or a Flatpak portal, or a group the user is not in.
      // Offering a button that opens nothing is worse than offering none.
      expect(canOpenCameraSettings('macos'), isTrue);
      expect(canOpenCameraSettings('windows'), isTrue);
      expect(canOpenCameraSettings('linux'), isFalse);
      expect(canOpenCameraSettings('android'), isFalse);
    });

    test('each platform names the place a person has to go', () {
      // The words have to match what is actually on their screen, or the
      // instruction is useless to the non-technical person this app is for.
      expect(
        cameraSettingsHint('macos'),
        contains('System Settings'),
      );
      expect(cameraSettingsHint('macos'), contains('Camera'));
      expect(cameraSettingsHint('windows'), contains('Settings'));
      expect(cameraSettingsHint('linux'), isNot(contains('System Settings')));
    });

    test('the settings command matches the platform that can be opened', () {
      // The two have to agree: a platform offered a button must have a
      // command behind it, and one without a command must not be offered.
      for (final platform in ['macos', 'windows', 'linux', 'android']) {
        expect(
          cameraSettingsCommand(platform) != null,
          canOpenCameraSettings(platform),
          reason: platform,
        );
      }
    });

    test('macOS opens the camera page, not the settings app', () {
      // Dropping the ?Privacy_Camera fragment lands on whatever pane was
      // open last, which for a non-technical person is the same as no
      // button at all.
      final command = cameraSettingsCommand('macos')!;
      expect(command.executable, 'open');
      expect(command.arguments.single, contains('Privacy_Camera'));
    });

    test('macOS is told it will not ask again', () {
      // The single most useful fact for someone who clicked Don't Allow,
      // and the reason a "try again" button would be a lie on this platform.
      expect(cameraSettingsHint('macos').toLowerCase(), contains('again'));
    });
  });
}
