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
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'capability_hint.dart';
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

  /// Whether this is a hand-held device, which changes which camera to
  /// open and at what resolution.
  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// The lens to prefer. A phone points its back camera at the other
  /// screen; everything else has one camera and takes it.
  static CameraLensDirection get _preferredLens =>
      _isMobile ? CameraLensDirection.back : CameraLensDirection.front;

  final CameraPlatform _platform;

  int? _cameraId;
  StreamSubscription<CameraImageData>? _frames;
  StreamSubscription<CameraInitializedEvent>? _initialised;
  final _payloads = StreamController<String>.broadcast();

  /// Width / height of the camera image, once known.
  ///
  /// The preview must be drawn at this ratio. Stretching it to fill a box
  /// of some other shape distorts the image, which is both ugly and
  /// counterproductive: a squashed QR is harder for the user to aim at.
  double? _aspectRatio;
  double? get aspectRatio => _aspectRatio;

  /// Capture resolution, once the backend has published it.
  ///
  /// Kept alongside [aspectRatio] because the two answer different
  /// questions: the ratio shapes the preview, the pixel count decides
  /// whether this camera can resolve a dense code at all.
  int? _previewWidth;
  int? _previewHeight;

  /// How many frames have been looked at, and how many held a code.
  ///
  /// Without this the user cannot tell a camera that is working but
  /// seeing nothing from one that is not running at all — the complaint
  /// that prompted it.
  int _framesSeen = 0;
  int _framesDecoded = 0;
  int get framesSeen => _framesSeen;
  int get framesDecoded => _framesDecoded;

  /// Outcomes of the last [_windowSize] frames: true when a code was read.
  ///
  /// A rolling window rather than a running total, because what matters is
  /// how the camera is doing *now*. Totals since the scan began keep
  /// reporting a bad start long after the user has fixed their aim, which
  /// is the opposite of useful for a live indicator.
  final List<bool> _recent = [];
  static const int _windowSize = 30;

  /// When the first frame arrived, for measuring the real frame rate.
  DateTime? _firstFrameAt;

  /// Share of the last 30 frames that held a readable code, or null
  /// before there are enough to mean anything.
  ///
  /// The most honest signal available: it reflects focus, lighting,
  /// distance and a steady hand all at once, none of which resolution or
  /// frame rate reveal on their own.
  double? get recentDecodeRate {
    if (_recent.length < 10) return null;
    final hits = _recent.where((ok) => ok).length;
    return hits / _recent.length;
  }

  /// Frames per second this camera actually delivers, or null before
  /// there is enough to measure.
  ///
  /// Measured rather than taken from the camera's own claim, which is a
  /// maximum under good light and not what a dim room produces.
  double? get measuredFps {
    final start = _firstFrameAt;
    if (start == null || _framesSeen < 10) return null;
    final seconds = DateTime.now().difference(start).inMilliseconds / 1000;
    if (seconds <= 0) return null;
    return _framesSeen / seconds;
  }

  /// Everything measured about this camera, or null when there is not yet
  /// enough to be worth sending.
  ///
  /// Null until both the frame rate and the resolution are known. A
  /// partial measurement is worse than none: [suggestEmission] reasons
  /// about resolution, and a zero there would read as "tiny camera" and
  /// suggest a needlessly slow stream.
  CameraCapability? get capability {
    final fps = measuredFps;
    final width = _previewWidth;
    final height = _previewHeight;
    if (fps == null || width == null || height == null) return null;
    return CameraCapability(
      framesPerSecond: fps,
      width: width,
      height: height,
      decodeRate: recentDecodeRate,
    );
  }

  /// Fires whenever [framesSeen] or [framesDecoded] changes, so a widget
  /// can rebuild without polling.
  final _activity = StreamController<void>.broadcast();
  Stream<void> get activity => _activity.stream;

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

    // On a phone the back camera is the one pointed at the other screen;
    // a laptop or an external webcam has no "back" and takes whatever is
    // there. Picking the first camera unconditionally gave a phone its
    // selfie camera.
    final preferred = cameras.firstWhere(
      (c) => c.lensDirection == _preferredLens,
      orElse: () => cameras.first,
    );

    try {
      // Resolution is a trade, and it falls differently per platform.
      //
      // Desktop uses low: a webcam fills the frame with the code, fewer
      // pixels is less work, and camera_desktop on Linux can fail to
      // initialise above low outright.
      //
      // A phone is held further back and its sensor is much larger, so
      // low there resolves a dense code poorly. Medium is the smallest
      // setting that reads one reliably at arm's length.
      final id = await _platform.createCameraWithSettings(
        preferred,
        MediaSettings(
          resolutionPreset:
              _isMobile ? ResolutionPreset.medium : ResolutionPreset.low,
          enableAudio: false,
        ),
      );
      // The aspect ratio is a refinement, not a requirement: a backend
      // that does not publish this event still scans, it just cannot tell
      // us the shape of its image. Letting an UnimplementedError here
      // abort start() would trade a correct preview for no camera at all.
      try {
        _initialised = _platform.onCameraInitialized(id).listen((event) {
          if (event.previewHeight > 0) {
            _aspectRatio = event.previewWidth / event.previewHeight;
            _previewWidth = event.previewWidth.round();
            _previewHeight = event.previewHeight.round();
            if (!_activity.isClosed) _activity.add(null);
          }
        });
      } catch (_) {
        _aspectRatio = null;
      }
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
    _framesSeen++;
    _firstFrameAt ??= DateTime.now();
    if (!_activity.isClosed) _activity.add(null);
    try {
      final payload = await compute(decodeFrame, frame);
      _recent.add(payload != null);
      if (_recent.length > _windowSize) _recent.removeAt(0);
      if (payload != null && !_payloads.isClosed) {
        _framesDecoded++;
        _activity.add(null);
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
    await _initialised?.cancel();
    _initialised = null;

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
    await _activity.close();
  }
}
