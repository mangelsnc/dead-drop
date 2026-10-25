/// Tests for the scanner capability check (app/lib/src/qr_scanning.dart).
///
/// The bug this guards against is a message, not a crash. On Linux the
/// scanner plugin has no implementation, and the app reported
/// "No camera detected on this device" — which blames the user's hardware
/// for a gap in ours and sends them to check cables and permissions that
/// were never the problem.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/qr_scanning.dart';

void main() {
  group('canScanQr', () {
    test('matches the platforms mobile_scanner actually implements', () {
      // mobile_scanner 5.2.3 declares android, ios, macos and web. Web is
      // not a target here, so three platforms can scan and the rest cannot.
      // If this fails, either the dependency changed or the check drifted —
      // both worth a human looking.
      final expected = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
      expect(canScanQr, expected);
    });

    test('a platform either scans or explains why not, never both', () {
      if (canScanQr) {
        expect(scanUnavailableReason, isNull);
      } else {
        expect(scanUnavailableReason, isNotNull);
        expect(scanUnavailableReason, isNotEmpty);
      }
    });
  });

  group('scanUnavailableReason', () {
    test('never blames the camera or the user', () {
      final reason = scanUnavailableReason;
      if (reason == null) return; // this platform scans; nothing to check

      final lower = reason.toLowerCase();
      // The exact wording that was wrong, and its neighbours. A message
      // telling someone with a working webcam that no camera was detected
      // costs them time on the wrong problem.
      expect(lower, isNot(contains('no camera detected')));
      expect(lower, isNot(contains('permission denied')));
      expect(lower, isNot(contains('check your system settings')));
    });

    test('says the feature is missing, and what to do instead', () {
      final reason = scanUnavailableReason;
      if (reason == null) return;

      // Pinned as behaviour, not wording: the message has to name the
      // platform, absolve the hardware, and point at the path that works.
      expect(reason, contains(Platform.operatingSystem));
      expect(reason.toLowerCase(), contains('your camera is fine'));
      expect(reason.toLowerCase(), contains('key field'));
    });
  });
}
