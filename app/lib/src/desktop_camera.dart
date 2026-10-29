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

  /// The capture resolution, which decides the densest code that can be
  /// read at all. See the note at the call site.
  static ResolutionPreset get _resolutionPreset =>
      resolutionPresetFor(Platform.operatingSystem);

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

  /// The ratio of the image as it appears on screen.
  ///
  /// Distinct from [aspectRatio], which describes the sensor. On Android
  /// the sensor is mounted sideways — a phone's rear camera reports 90 or
  /// 270 degrees — and `buildPreview` turns the image to match the
  /// screen, so what the user sees is the sensor's ratio inverted.
  ///
  /// This is the one to lay the preview out with. Using the sensor's
  /// ratio instead put a portrait image into a landscape box and
  /// stretched it: reported from a phone as `sensor 720x480 · rot 90° ·
  /// ratio 1.50`, where the displayed image is really 0.67.
  double? get displayAspectRatio {
    final r = _aspectRatio;
    if (r == null) return null;
    final rotated = (_sensorOrientation ?? 0) % 180 != 0;
    return rotated ? 1 / r : r;
  }

  /// Capture resolution, once the backend has published it.
  ///
  /// Kept alongside [aspectRatio] because the two answer different
  /// questions: the ratio shapes the preview, the pixel count decides
  /// whether this camera can resolve a dense code at all.
  int? _previewWidth;
  int? _previewHeight;

  /// What the platform said about this camera, for on-screen diagnosis.
  ///
  /// The preview was stretched on a phone through three attempts at
  /// fixing it, each from a different guess about which of these numbers
  /// was wrong. Showing them is cheaper than guessing a fourth time.
  String get debugGeometry {
    final w = _previewWidth, h = _previewHeight;
    if (w == null || h == null) return 'geometry: unknown';
    final fps = measuredFps;
    // The share of delivered frames dropped because a decode was
    // already running. This is the one number that says whether
    // decoding on the Dart thread is costing anything: a native
    // decoder on its own thread would not drop these. Low means the
    // reader keeps up and swapping it would buy nothing.
    final dropped = _framesDelivered == 0
        ? 0
        : (_framesWhileBusy / _framesDelivered * 100).round();
    return 'sensor ${w}x$h · rot ${_sensorOrientation ?? '?'}°'
        ' · shown ${(displayAspectRatio ?? 0).toStringAsFixed(2)}\n'
        'cam ${fps == null ? '?' : fps.toStringAsFixed(1)} fps'
        ' · got $_framesDelivered · decoded $_framesSeen'
        ' · read $_framesDecoded\n'
        'busy-dropped $_framesWhileBusy ($dropped%)';
  }

  int? _sensorOrientation;

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
  /// How many frames a second the camera actually delivers.
  ///
  /// Counts every delivered frame, including those dropped because a
  /// decode was already running. It used to count only decoded frames,
  /// which measured this app's throughput instead: on a phone that read
  /// far below the camera's real rate, and since the emission hint asks
  /// for most of this figure, it fed back into a slower and slower
  /// suggestion.
  double? get measuredFps {
    final start = _firstFrameAt;
    if (start == null || _framesDelivered < 10) return null;
    final seconds = DateTime.now().difference(start).inMilliseconds / 1000;
    if (seconds <= 0) return null;
    return _framesDelivered / seconds;
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

  /// The last payload handed to [payloads], for suppressing the repeats
  /// a fast camera makes of one slow-changing code. Only the immediately
  /// previous one: the sender re-emits earlier frames by design, and a
  /// longer memory would drop those legitimately.
  String? _lastPayload;

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
          // What limits a scan is pixels per module, not frame rate.
          //
          // A 512-byte chunk is a 105-module code. For a decoder to get
          // the ~3 samples per module it needs, that code has to land on
          // some 315 pixels of sensor -- so the capture width sets a
          // floor on how dense a code can be read, and it is the first
          // thing to check when frames arrive and nothing decodes.
          //
          // low is 320x240, where even a code filling the frame gets
          // about 1.5 pixels per module. That was the desktop default
          // and it could not read a phone held in front of the webcam at
          // any distance: backing off to fit the code in frame only made
          // each module smaller. Reported from macOS as "sensor 320x240
          // ... seen 305 · read 0".
          //
          // Linux is the exception: camera_linux can fail to initialise
          // above medium, and a scanner that will not start is worse
          // than one that needs a steadier hand.
          resolutionPreset: _resolutionPreset,
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
            // The sensor's own ratio, unrotated on purpose.
            //
            // On Android, buildPreview wraps the texture in CameraX's
            // RotatedPreviewDelegate: the plugin has already turned the
            // image to match the screen. Rotating this figure as well
            // double-corrected it, which is why the preview kept coming
            // out stretched horizontally after the previous attempt.
            //
            // This value is therefore only a hint for laying the preview
            // out on platforms that do not rotate for us; the widget is
            // free to keep its own shape. See desktop_scanner_view.dart.
            _sensorOrientation = preferred.sensorOrientation;
            _aspectRatio = event.previewWidth / event.previewHeight;
            // The measurement keeps the sensor's own numbers: how many
            // pixels the camera captures is what decides whether it can
            // resolve a dense code, and that does not change with how
            // the image is turned for display.
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

  /// Frames the camera delivered while a decode was already running.
  ///
  /// The difference between "the camera is slow" and "we cannot keep up
  /// with it". If this climbs while [_framesSeen] crawls, the decoder is
  /// the bottleneck; if both crawl, the camera is not delivering.
  int _framesWhileBusy = 0;

  /// Every frame the camera has delivered, decoded or not.
  ///
  /// Distinct from [_framesSeen], which counts only the frames that
  /// reached the decoder. The difference is not small — a frame
  /// arriving while a decode is in flight is dropped — and measuring
  /// the camera with [_framesSeen] measures how fast this app can
  /// process, not how fast the camera samples. The emission hint is
  /// derived from this rate, so getting it wrong tells the sender to
  /// emit faster than the camera can see.
  int _framesDelivered = 0;

  Future<void> _onFrame(CameraImageData frame) async {
    // Counted before anything can drop the frame: this is the camera's
    // own rate, which is what the emission hint must be derived from.
    _framesDelivered++;
    _firstFrameAt ??= DateTime.now();

    if (_decoding) {
      _framesWhileBusy++;
      return;
    }
    if (_payloads.isClosed) return;
    _decoding = true;
    _framesSeen++;
    if (!_activity.isClosed) _activity.add(null);
    try {
      // Decoded here, not on a spawned isolate.
      //
      // compute() starts a fresh isolate for every frame. On the desktop
      // this was affordable; on a phone the spawn costs far more than
      // the decode it wraps — and while it runs, the _decoding guard
      // above drops every frame the camera delivers. The scanner spent
      // its time creating isolates instead of reading codes, which is
      // why frames arrived but chunks did not.
      //
      // The decode itself is 5.3 ms median on this project's own frames.
      // That fits inside a frame interval at any usable rate, so the
      // preview does not stutter for it.
      final payload = decodeFrame(frame);
      _recent.add(payload != null);
      if (_recent.length > _windowSize) _recent.removeAt(0);
      if (payload != null && !_payloads.isClosed) {
        _framesDecoded++;
        _activity.add(null);
        // Consecutive reads of the same code are dropped.
        //
        // The camera runs far faster than the sender's display — 30 fps
        // against 8 — so each QR is captured several times over. Passing
        // every copy on is harmless to the decoder, which ignores
        // duplicates, but it is not free upstream: the receive screen
        // counted 3,332 frames for 49 chunks, where the code needs about
        // 1.15, because most of that work was the same frame again.
        //
        // mobile_scanner did this with DetectionSpeed.noDuplicates; the
        // replacement had no equivalent, and this is it.
        if (payload != _lastPayload) {
          _lastPayload = payload;
          _payloads.add(payload);
        }
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

/// The capture resolution to use on [operatingSystem].
///
/// Separated from the camera so the choice can be tested without one, and
/// taking the platform as a value rather than reading it, so every branch
/// is reachable from a test on any machine.
///
/// Linux is held at medium because camera_linux can fail to initialise
/// above it, and a scanner that will not start is worse than one that
/// needs a steadier hand. Everywhere else takes high: low is 320x240,
/// which cannot resolve any code this app emits.
ResolutionPreset resolutionPresetFor(String operatingSystem) =>
    operatingSystem == 'linux'
        ? ResolutionPreset.medium
        : ResolutionPreset.high;

/// The capture width, in pixels, of each [ResolutionPreset] this app uses.
///
/// The `camera` package defines presets as target resolutions; a backend
/// may hand back something near them. These are the nominal figures, and
/// they are what the pixels-per-module arithmetic is done against.
const Map<ResolutionPreset, int> kPresetCaptureWidth = {
  ResolutionPreset.low: 320,
  ResolutionPreset.medium: 720,
  ResolutionPreset.high: 1280,
  ResolutionPreset.veryHigh: 1920,
};

/// How many camera pixels fall on one QR module, for a code of
/// [moduleCount] modules captured at [captureWidth], assuming the code
/// occupies [frameFraction] of the frame's width.
///
/// A decoder needs roughly three; below two it cannot work at all. This
/// is the figure that decides whether a scan is possible before frame
/// rate, decoder or lighting are worth considering.
double pixelsPerModule({
  required int captureWidth,
  required int moduleCount,
  double frameFraction = 0.6,
}) =>
    captureWidth * frameFraction / moduleCount;
