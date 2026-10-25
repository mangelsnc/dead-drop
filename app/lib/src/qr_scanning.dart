/// qr_scanning.dart — whether this platform can scan a QR code at all.
///
/// `mobile_scanner` 5.2.3 ships implementations for android, ios, macos and
/// web only. On Linux and Windows the plugin resolves to nothing, so a scan
/// attempt fails no matter what hardware is attached.
///
/// That distinction matters to the person using the app. A Linux user with a
/// perfectly good webcam plugged in was being told "No camera detected on
/// this device", which blames their hardware for a gap in ours and sends
/// them off to check cables and permissions that were never the problem.
/// Where this returns false, the UI says the platform cannot scan and points
/// at the way that does work: typing or pasting the key.
library;

import 'dart:io';

/// Whether a QR scanner exists on this platform.
///
/// Deliberately a capability check rather than a negative list: when a Linux
/// scanner does land, this is the one place that changes.
bool get canScanQr => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// Why scanning is unavailable, for the UI to show in place of a camera.
///
/// Null when [canScanQr] is true.
String? get scanUnavailableReason => canScanQr
    ? null
    : 'Scanning with the camera is not available on '
        '${Platform.operatingSystem} yet — the QR scanner this app uses has '
        'no implementation for this platform. Your camera is fine; the '
        'feature is missing. Use the key field instead.';
