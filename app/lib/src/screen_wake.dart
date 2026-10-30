/// screen_wake.dart — keeps the screen awake while a transfer is running.
///
/// A transfer is the one time this app must not let the display sleep. The
/// sender is showing animated QR codes and the receiver is pointing a camera
/// at them; if either screen dims or locks the transfer stalls, and on the
/// sender side locking the phone hides the very thing the other device is
/// reading.
///
/// **Why not `wakelock_plus`.** It would do this, but `flutter pub add
/// --dry-run` reports it pulling in ten packages. This app's argument is that
/// it has very little attack surface and that every dependency is auditable;
/// ten transitive packages to stop a screen dimming is a bad trade, and
/// CONTRIBUTING.md asks that new dependencies be justified before they are
/// added. What the plugin does on the two platforms we need is one platform
/// call each, so we make that call ourselves.
///
/// Android and iOS only. Desktop has no equivalent reachable this way, and a
/// laptop sleeping mid-transfer is both less likely and less costly — its
/// owner is sitting in front of it. Elsewhere these are no-ops.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Our own channel. The Android and iOS sides are implemented in
/// MainActivity.kt and AppDelegate.swift respectively.
const MethodChannel _channel = MethodChannel('dev.deaddrop/screen_wake');

/// Overrides the platform check in tests.
///
/// `Platform.isAndroid` reads dart:io, which a widget test cannot fake, so
/// without this seam the lifecycle these functions implement could only be
/// verified by hand on a phone — and it already regressed once that way.
@visibleForTesting
bool? debugSupportedOverride;

bool get _supported =>
    debugSupportedOverride ?? (Platform.isAndroid || Platform.isIOS);

/// Whether the wakelock is currently believed to be held. Tracked so a
/// double release cannot leave the screen pinned on, and so [isHeld] can be
/// asserted in tests.
bool _held = false;

/// Whether this process is currently asking the platform to keep the screen
/// on. Exposed for tests and for the UI to reason about its own state.
bool get isScreenAwakeHeld => _held;

/// Whether this platform can set the screen's brightness for a transfer.
///
/// The same platforms that can hold the screen awake: Android sets it on
/// its own window, iOS on the device. A desktop window has no brightness
/// of its own, so the send screen hides the control there rather than
/// offering one that does nothing.
bool get supportsTransferBrightness => _supported;

/// The brightness a transfer runs at when nothing else is chosen.
///
/// Full. Against a phone camera this is right, and it is what the screen
/// did before the level was adjustable.
const double kDefaultTransferBrightness = 1.0;

/// Asks the platform to keep the screen on for the duration of a transfer,
/// at [brightness] (0 dimmest, 1 full).
///
/// Safe to call when already held — a repeat is ignored rather than
/// re-applied, so changing the level means releasing first. Failures are
/// swallowed: a screen that dims is an annoyance, and must never be the
/// reason the app falls over.
///
/// [brightness] exists because full is not right against every camera. A
/// transfer from a phone to a Logitech StreamCam failed with the screen at
/// full: the webcam's auto-exposure stopped down and the code's dark
/// modules washed out to grey. Lowering the screen is the only lever the
/// sender has over the receiver's exposure.
Future<void> keepScreenAwake({
  double brightness = kDefaultTransferBrightness,
}) async {
  if (!_supported || _held) return;
  try {
    await _channel.invokeMethod<void>('keepAwake', {
      'level': brightness.clamp(0.0, 1.0),
    });
    _held = true;
  } on PlatformException {
    // Deliberately ignored — see the doc comment.
  } on MissingPluginException {
    // The native side is not present on this platform build. Same reasoning.
  }
}

/// Releases the request, letting the screen sleep normally again.
///
/// Must be called when a transfer ends — including on error, on cancel and
/// on dispose. A wakelock left held drains the battery of a device whose
/// owner may have no way to charge it.
Future<void> allowScreenSleep() async {
  if (!_supported || !_held) return;
  try {
    await _channel.invokeMethod<void>('allowSleep');
  } on PlatformException {
    // Ignored, but the flag is cleared regardless: believing we still hold a
    // lock we have lost would stop us ever asking for it again.
  } on MissingPluginException {
    // As above.
  } finally {
    _held = false;
  }
}

/// Resets the tracked state. Tests only — the platform side is untouched.
@visibleForTesting
void debugResetScreenWake() {
  _held = false;
  debugSupportedOverride = null;
}
