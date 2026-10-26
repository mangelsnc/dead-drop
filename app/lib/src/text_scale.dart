/// text_scale.dart — how large the app draws the strings people have to
/// read character by character.
///
/// Fingerprints, public keys and passphrases are set in a monospaced face
/// at a fixed size. That size was chosen on a developer's screen, and 64
/// hex characters at 13px is genuinely hard to read — which matters more
/// here than in most apps, because the whole point of showing a
/// fingerprint is that a person compares it against another one. A
/// comparison nobody can see properly is a security control that does not
/// work.
///
/// This is a preference of the app's own rather than a reading of the
/// system's. Someone who can read the rest of the interface comfortably
/// may still need these particular strings larger, and asking them to
/// change a system-wide setting to fix one screen is asking too much.
///
/// Stored as a plain file in the app support directory. It is not secret,
/// it is needed before the keychain is reachable at startup, and a
/// corrupt or missing value simply means the default.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The size technical text is drawn at when nothing has been chosen.
///
/// Matches what the app used before this was configurable, so an existing
/// user sees no change until they ask for one.
const double kDefaultTechnicalTextSize = 13;

/// The range the setting allows.
///
/// The floor is the old fixed size: this control exists to make text
/// bigger, and offering "smaller than the size people already found hard
/// to read" would be a trap. The ceiling is where a 64-character key stops
/// fitting a phone's width even wrapped, past which the control stops
/// helping and starts breaking layouts.
const double kMinTechnicalTextSize = 13;
const double kMaxTechnicalTextSize = 28;

/// How much one press of the larger/smaller control moves it.
const double kTechnicalTextSizeStep = 1.5;

/// Reads and writes the preference.
///
/// [directory] is injectable so tests do not touch the real app support
/// directory; production resolves it through `path_provider`.
class TextScaleStore {
  TextScaleStore({this.directory});

  final Directory? directory;
  double? _cached;

  static const _fileName = 'text_scale';

  Future<File> _file() async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// The stored size, or [kDefaultTechnicalTextSize].
  ///
  /// Never throws. A missing file is the normal first-run case; an
  /// unreadable or nonsensical one means a default rather than a broken
  /// screen, since nothing here is worth failing a launch over.
  Future<double> read() async {
    if (_cached != null) return _cached!;
    try {
      final file = await _file();
      if (!file.existsSync()) return _cached = kDefaultTechnicalTextSize;
      final value = double.tryParse(await file.readAsString());
      _cached = value == null ? kDefaultTechnicalTextSize : clamp(value);
    } catch (_) {
      _cached = kDefaultTechnicalTextSize;
    }
    return _cached!;
  }

  /// Stores [size], clamped to the allowed range.
  ///
  /// A failed write is swallowed: the new size still applies for this
  /// session, and a preference that does not survive a restart is a far
  /// smaller problem than an error dialog over a font size.
  Future<void> write(double size) async {
    _cached = clamp(size);
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(_cached!.toString());
    } catch (_) {
      // See above.
    }
  }

  /// Forgets the cached value. Tests only.
  @visibleForTesting
  void debugReset() => _cached = null;
}

/// Brings [size] within the allowed range.
double clamp(double size) =>
    size.clamp(kMinTechnicalTextSize, kMaxTechnicalTextSize).toDouble();

/// The next size up, or the current one when already at the ceiling.
double nextLarger(double size) => clamp(size + kTechnicalTextSizeStep);

/// The next size down, or the current one when already at the floor.
double nextSmaller(double size) => clamp(size - kTechnicalTextSizeStep);
