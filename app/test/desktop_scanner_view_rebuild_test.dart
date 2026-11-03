/// How often does the camera tell the view to repaint while it reads?
///
/// Reported from macOS: the receive screen opened fine, and the camera
/// then failed the moment the fountain of codes started, with
/// `CameraException(initialization_timeout, no frames received)`.
///
/// Three things combine to produce that:
///
///  * `DesktopScannerView` calls `setState` on every `activity` event, and
///    `DesktopCameraScanner` emits one per frame — before decoding, so a
///    frame holding no code still fires one. A webcam runs at about 30 fps.
///  * A rebuild of the receive screen costs 132 ms on an M3 and 542 ms on
///    a Slimbook running Kali, both measured on 2026-11-03: the QR widget
///    rebuilds from scratch every time. Thirty a second cannot be served.
///  * `DesktopCameraScanner.start` awaits `initializeCamera` on that same
///    isolate. Saturated, the await does not return in time and the plugin
///    raises its initialisation timeout. The camera was never broken —
///    nothing was free to start it.
///
/// These pin the rate at its source: however fast frames arrive, the
/// activity stream must stay slow enough for a 132 ms rebuild to keep up,
/// and must not stop entirely, or the status line the user aims by freezes.
///
/// Written as plain `test`, not `testWidgets`: the fake async clock a
/// widget test installs never drains the real microtask a broadcast stream
/// delivers on, so frames added under it never reach the scanner at all.
/// An earlier draft of this file did exactly that and passed while
/// measuring nothing — which is why the first check below is that the
/// frames arrived.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:dead_drop/src/desktop_camera.dart';
import 'package:flutter_test/flutter_test.dart';

/// A camera whose frames the test delivers by hand.
class _DrivenCameraPlatform extends CameraPlatform {
  final StreamController<CameraImageData> frames =
      StreamController<CameraImageData>.broadcast();

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
        CameraDescription(
          name: 'fake',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 0,
        ),
      ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings? mediaSettings,
  ) async =>
      1;

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(CameraInitializedEvent(
        cameraId,
        640,
        480,
        ExposureMode.auto,
        true,
        FocusMode.auto,
        true,
      ));

  @override
  Future<void> initializeCamera(int cameraId,
      {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {}

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(int cameraId,
          {CameraImageStreamOptions? options}) =>
      frames.stream;

  @override
  Future<void> dispose(int cameraId) async {}
}

/// A frame of flat grey. No QR in it: `activity` fires before the decode,
/// so what is counted is frames arriving, not codes being read.
CameraImageData _blankFrame() {
  const width = 64;
  const height = 48;
  return CameraImageData(
    format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 0),
    planes: [
      CameraImagePlane(
        bytes: Uint8List.fromList(List<int>.filled(width * height * 4, 0x80)),
        bytesPerRow: width * 4,
        width: width,
        height: height,
      ),
    ],
    width: width,
    height: height,
    lensAperture: null,
    sensorExposureTime: null,
    sensorSensitivity: null,
  );
}

/// Runs [frameCount] frames through a scanner [everyMillis] apart and
/// reports how many repaints the view would have been asked for.
Future<({int events, int framesSeen})> _run({
  required int frameCount,
  int everyMillis = 33,
}) async {
  final platform = _DrivenCameraPlatform();
  final scanner = DesktopCameraScanner(platform: platform);
  addTearDown(scanner.dispose);
  addTearDown(platform.frames.close);

  await scanner.start();

  var events = 0;
  final sub = scanner.activity.listen((_) => events++);
  addTearDown(sub.cancel);

  for (var i = 0; i < frameCount; i++) {
    platform.frames.add(_blankFrame());
    await Future<void>.delayed(Duration(milliseconds: everyMillis));
  }
  // Let a trailing throttled event land.
  await Future<void>.delayed(const Duration(milliseconds: 300));

  return (events: events, framesSeen: scanner.framesSeen);
}

void main() {
  test('a second of camera does not ask for a repaint per frame', () async {
    // 30 frames at 33 ms is one second of an ordinary webcam.
    final result = await _run(frameCount: 30);

    // The frames really arrived. Without this the count below could be
    // low because nothing happened, which is how the first version of
    // this test passed against unfixed code.
    expect(result.framesSeen, greaterThan(20),
        reason: 'the fake camera did not deliver; the measurement below '
            'would be meaningless');

    expect(result.events, lessThan(12),
        reason: '${result.framesSeen} frames produced ${result.events} '
            'repaint requests. Each rebuild costs 132 ms on an M3 and '
            '542 ms on the Slimbook, and the isolate serving them is the '
            'one camera start-up awaits.');
  });

  test('the view keeps being told to repaint', () async {
    // The other half. A throttle that never fires would pass the test
    // above and freeze the status line the user aims the camera by.
    final result = await _run(frameCount: 30);

    expect(result.events, greaterThan(1),
        reason: 'the status line has to keep moving while the camera '
            'reads, or the user cannot tell whether aiming is helping');
  });

  test('the rate follows the clock, not the frame count', () async {
    // What separates a real throttle from a cheap "every Nth frame"
    // counter: the latter still scales with the camera's rate, so a
    // faster webcam would bring the problem straight back.
    // Both runs cover the same second of clock. The fast one delivers
    // five times the frames, so a frame counter gives it five times the
    // repaints while a clock gives it the same handful.
    //
    // Comparing equal frame counts at different rates does NOT catch
    // this: `_activityTick % 8` returns the same number of events for
    // the same number of frames however fast they arrive, and a mutation
    // to exactly that survived an earlier version of this test.
    final slow = await _run(frameCount: 20, everyMillis: 50);
    final fast = await _run(frameCount: 100, everyMillis: 10);

    expect(fast.framesSeen, greaterThan(50),
        reason: 'the fast run must actually have delivered frames');
    expect(fast.events, lessThan(slow.events * 2),
        reason: 'over the same second of clock, five times the frame rate '
            'produced ${fast.events} repaints against ${slow.events}. A '
            'throttle keyed to the clock gives both the same; one keyed '
            'to the frame count scales with the camera, and the problem '
            'returns on a faster webcam.');
  });
}
