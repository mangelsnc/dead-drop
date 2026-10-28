/// mobile_camera_measure.dart — measuring the camera behind `MobileScanner`.
///
/// The desktop scanner drives the camera itself, so it counts every frame it
/// is handed and knows how many held a readable code. `MobileScanner` gives
/// no such access: the only thing this app observes is a successful
/// detection. That difference is the whole reason this file exists, and it
/// bounds what can honestly be reported.
///
/// What can be measured: how often a code is successfully read, and the
/// resolution of the frames those reads came from (`BarcodeCapture.size`).
///
/// What cannot: the share of frames that failed. A frame the camera captured
/// and the decoder rejected is invisible here. [MobileCameraMeasure]
/// therefore reports a null decode rate rather than inventing one — a
/// fabricated rate would feed `suggestEmission` and make the sender slow a
/// stream that was reading perfectly well.
library;

import 'capability_hint.dart';

/// Successful detections per second, and the frame size they arrived at.
///
/// Fed one call per detection from the receive screen; [capability] turns
/// that into the measurement the handshake QR carries.
class MobileCameraMeasure {
  MobileCameraMeasure({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Detections are counted from the first one, not from when the camera
  /// opened: the gap while the user aims at the other screen is not the
  /// camera being slow, and counting it would understate the rate.
  DateTime? _firstDetectionAt;
  int _detections = 0;
  int? _width;
  int? _height;

  /// How many successful reads have been observed.
  int get detections => _detections;

  /// Records one successful detection at [width] x [height].
  ///
  /// A zero or negative dimension is ignored rather than stored: the
  /// resolution decides whether `suggestEmission` calls this a
  /// low-resolution camera, and a zero there reads as "tiny" and would
  /// suggest a needlessly slow stream.
  void recordDetection({required int width, required int height}) {
    _firstDetectionAt ??= _now();
    _detections++;
    if (width > 0 && height > 0) {
      _width = width;
      _height = height;
    }
  }

  /// Successful reads per second, or null before there is enough to mean
  /// anything.
  ///
  /// This is a floor on the camera's frame rate, never the frame rate
  /// itself: the camera may be delivering far more frames than yield a
  /// code. [capability] relies on that being a floor, not an estimate.
  double? get decodesPerSecond {
    final start = _firstDetectionAt;
    if (start == null || _detections < _minDetections) return null;
    final seconds = _now().difference(start).inMilliseconds / 1000;
    if (seconds <= 0) return null;
    return _detections / seconds;
  }

  /// Enough reads that the rate is not dominated by one lucky frame.
  static const int _minDetections = 10;

  /// What this camera managed, or null when there is not yet enough to be
  /// worth sending to the other device.
  ///
  /// `decodeRate` is deliberately null. On this path a failed frame is
  /// unobservable, so any number here would be a guess, and
  /// `suggestEmission` treats a low rate as a reason to slow the sender
  /// down. Reporting nothing leaves it reasoning from frame rate and
  /// resolution alone, which are both measured rather than inferred.
  CameraCapability? get capability {
    final rate = decodesPerSecond;
    final width = _width;
    final height = _height;
    if (rate == null || width == null || height == null) return null;
    return CameraCapability(
      framesPerSecond: rate,
      width: width,
      height: height,
      decodeRate: null,
    );
  }

  /// Forgets everything measured, for a fresh reading on the next scan.
  void reset() {
    _firstDetectionAt = null;
    _detections = 0;
    _width = null;
    _height = null;
  }
}
