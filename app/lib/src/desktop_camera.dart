/// desktop_camera.dart — a camera scanner for Linux and Windows.
///
/// Drives `camera_platform_interface` directly rather than going through
/// the `camera` package. The interface already exposes everything needed —
/// create, initialise, a frame stream and a preview widget — and the
/// `camera` package on top of it would pull in the Android, iOS and web
/// implementations this app does not use on desktop. `camera_desktop`
/// registers itself as the platform implementation; nothing else is
/// needed to reach it.
///
/// Decoding happens on a background isolate. At 12 fps each frame has
/// 83 ms, and decoding measures 5.3 ms, so this is not about speed: it is
/// that a frame arriving mid-paint must never make the preview stutter.
library;

import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'desktop_scanner.dart';

/// What went wrong, in words a person can act on.
///
/// The messages name the platform and say whether the fault is theirs to
/// fix, because "camera error" sends people to check cables that were
/// never the problem.
class DesktopCameraException implements Exception {
  const DesktopCameraException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A running camera that reports the QR payloads it sees.
///
/// Lifecycle: [start] once, listen to [payloads], then [dispose]. Calling
/// [start] twice is an error rather than a silent no-op — two scanners on
/// one camera is a bug worth seeing.
class DesktopCameraScanner {
  DesktopCameraScanner({CameraPlatform? platform})
      : _platform = platform ?? CameraPlatform.instance;

  final CameraPlatform _platform;

  int? _cameraId;
  StreamSubscription<CameraImageData>? _frames;
  final _payloads = StreamController<String>.broadcast();

  /// Whether a frame is being decoded right now.
  ///
  /// Frames arriving while one is in flight are dropped. Queueing them
  /// would build an unbounded backlog the moment decoding fell behind
  /// capture, and a stale frame is worth nothing here — the sender is
  /// already showing the next code.
  bool _decoding = false;

  /// Payloads read from the camera, in the order they were decoded.
  ///
  /// Duplicates are not filtered: the sender repeats frames by design and
  /// the receiver decides what is new. Filtering here would silently drop
  /// a legitimately repeated frame.
  Stream<String> get payloads => _payloads.stream;

  /// The camera's id once started, for [preview].
  int? get cameraId => _cameraId;

  /// Opens the first available camera and begins scanning.
  ///
  /// Throws [DesktopCameraException] when no camera is available or the
  /// platform has no implementation — both are conditions the UI should
  /// explain rather than retry.
  Future<void> start() async {
    if (_cameraId != null) {
      throw StateError('Scanner already started');
    }

    final List<CameraDescription> cameras;
    try {
      cameras = await _platform.availableCameras();
    } on MissingPluginException {
      throw const DesktopCameraException(
        'No camera support is available in this build.',
      );
    } on PlatformException catch (e) {
      throw DesktopCameraException(
        'Could not list cameras: ${e.message ?? e.code}',
      );
    }

    if (cameras.isEmpty) {
      throw const DesktopCameraException(
        'No camera found. Connect one and try again.',
      );
    }

    try {
      // Low resolution on purpose. A QR fills the frame, the decoder does
      // not need detail, and fewer pixels is less work per frame. It also
      // sidesteps a camera_desktop limitation: on Linux, initialising
      // above low can fail outright.
      final id = await _platform.createCameraWithSettings(
        cameras.first,
        const MediaSettings(
          resolutionPreset: ResolutionPreset.low,
          enableAudio: false,
        ),
      );
      await _platform.initializeCamera(id);
      _cameraId = id;
    } on PlatformException catch (e) {
      throw DesktopCameraException(
        'Could not open the camera: ${e.message ?? e.code}. '
        'Another application may be using it.',
      );
    }

    _frames = _platform.onStreamedFrameAvailable(_cameraId!).listen(
          _onFrame,
          onError: (Object e) => _payloads.addError(
            DesktopCameraException('The camera stopped: $e'),
          ),
        );
  }

  Future<void> _onFrame(CameraImageData frame) async {
    if (_decoding || _payloads.isClosed) return;
    _decoding = true;
    try {
      final payload = await compute(decodeFrame, frame);
      if (payload != null && !_payloads.isClosed) {
        _payloads.add(payload);
      }
    } catch (_) {
      // A frame that cannot be decoded is the normal case, and an isolate
      // that fails on one frame should not end the scan.
    } finally {
      _decoding = false;
    }
  }

  /// The live camera image, for showing the user what they are pointing at.
  ///
  /// Aiming a camera without seeing it is guesswork, so this is not
  /// optional decoration.
  Widget preview() {
    final id = _cameraId;
    if (id == null) {
      throw StateError('Call start() before preview()');
    }
    return _platform.buildPreview(id);
  }

  /// Stops the camera and releases it.
  ///
  /// Safe to call twice, and safe to call when [start] threw: a camera
  /// left open stays unavailable to every other application.
  Future<void> dispose() async {
    await _frames?.cancel();
    _frames = null;

    final id = _cameraId;
    _cameraId = null;
    if (id != null) {
      try {
        await _platform.dispose(id);
      } catch (_) {
        // Already gone, or the platform is shutting down. Nothing useful
        // to do, and throwing here would mask the real error.
      }
    }

    await _payloads.close();
  }
}
