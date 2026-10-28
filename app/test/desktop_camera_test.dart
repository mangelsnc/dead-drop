/// Tests for the desktop camera scanner (app/lib/src/desktop_camera.dart).
///
/// Driven through a fake `CameraPlatform`, so these run without a camera
/// and cover the cases a real one makes hard to reach on purpose: no
/// camera attached, the camera held by another application, the stream
/// dying mid-scan, and frames arriving faster than they decode.
library;

import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

import 'package:dead_drop/src/desktop_camera.dart';

/// A CameraPlatform that reports whatever the test tells it to.
class _FakeCameraPlatform extends CameraPlatform {
  _FakeCameraPlatform({
    this.cameras = const [
      CameraDescription(
        name: 'fake',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 0,
      ),
    ],
    this.availableCamerasThrows,
    this.createThrows,
  });

  final List<CameraDescription> cameras;
  final Object? availableCamerasThrows;
  final Object? createThrows;

  final frames = StreamController<CameraImageData>.broadcast();
  int disposeCalls = 0;
  bool streamRequested = false;

  @override
  Future<List<CameraDescription>> availableCameras() async {
    if (availableCamerasThrows != null) throw availableCamerasThrows!;
    return cameras;
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings? mediaSettings,
  ) async {
    if (createThrows != null) throw createThrows!;
    return 7;
  }

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
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    streamRequested = true;
    return frames.stream;
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox(key: Key('preview'));

  @override
  Future<void> dispose(int cameraId) async => disposeCalls++;
}

/// A BGRA frame containing [payload] as a QR code.
CameraImageData _frame(String payload) {
  final qr = QrImage(QrCode.fromData(
    data: payload,
    errorCorrectLevel: QrErrorCorrectLevel.L,
  ));
  const scale = 4, quiet = 8;
  final side = (qr.moduleCount + quiet * 2) * scale;
  final stride = side * 4;
  final bytes = Uint8List(stride * side)..fillRange(0, stride * side, 0xFF);

  for (var row = 0; row < qr.moduleCount; row++) {
    for (var col = 0; col < qr.moduleCount; col++) {
      if (!qr.isDark(row, col)) continue;
      for (var dy = 0; dy < scale; dy++) {
        for (var dx = 0; dx < scale; dx++) {
          final i = ((row + quiet) * scale + dy) * stride +
              ((col + quiet) * scale + dx) * 4;
          bytes[i] = bytes[i + 1] = bytes[i + 2] = 0x00;
        }
      }
    }
  }

  return CameraImageData(
    format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: null),
    planes: [CameraImagePlane(bytes: bytes, bytesPerRow: stride)],
    width: side,
    height: side,
  );
}

/// A platform that does not publish camera dimensions, as the base class
/// does by default.
class _NoInitEventPlatform extends _FakeCameraPlatform {
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      throw UnimplementedError('onCameraInitialized() is not implemented.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('start', () {
    test('opens the camera and subscribes to frames', () async {
      final platform = _FakeCameraPlatform();
      final scanner = DesktopCameraScanner(platform: platform);
      addTearDown(scanner.dispose);

      await scanner.start();

      expect(scanner.cameraId, 7);
      expect(platform.streamRequested, isTrue);
    });

    test('explains when no camera is attached', () async {
      final scanner = DesktopCameraScanner(
        platform: _FakeCameraPlatform(cameras: const []),
      );

      await expectLater(
        scanner.start(),
        throwsA(isA<DesktopCameraException>().having(
          (e) => e.message, 'message', contains('No camera found'))),
      );
    });

    test('explains when the build has no camera support', () async {
      // A desktop build without camera_desktop registered. Saying "no
      // camera found" here would send the user to check their hardware.
      final scanner = DesktopCameraScanner(
        platform: _FakeCameraPlatform(
          availableCamerasThrows: MissingPluginException('none'),
        ),
      );

      await expectLater(
        scanner.start(),
        throwsA(isA<DesktopCameraException>().having(
          (e) => e.message, 'message', contains('No camera support'))),
      );
    });

    test('suggests the likely cause when the camera is busy', () async {
      final scanner = DesktopCameraScanner(
        platform: _FakeCameraPlatform(
          createThrows: PlatformException(code: 'EBUSY', message: 'in use'),
        ),
      );

      await expectLater(
        scanner.start(),
        throwsA(isA<DesktopCameraException>().having((e) => e.message,
            'message', contains('Another application'))),
      );
    });

    test('starts even when the platform cannot report its dimensions',
        () async {
      // The aspect ratio is a refinement, not a requirement. A backend
      // that does not publish the event should still scan — trading a
      // correct preview shape for no camera at all is a bad deal.
      final scanner = DesktopCameraScanner(platform: _NoInitEventPlatform());
      addTearDown(scanner.dispose);

      await scanner.start();

      expect(scanner.cameraId, 7);
      expect(scanner.aspectRatio, isNull);
    });

    test('learns the camera\'s aspect ratio', () async {
      final scanner = DesktopCameraScanner(platform: _FakeCameraPlatform());
      addTearDown(scanner.dispose);

      await scanner.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(scanner.aspectRatio, closeTo(640 / 480, 0.001));
    });

    test('refuses to start twice', () async {
      final scanner = DesktopCameraScanner(platform: _FakeCameraPlatform());
      addTearDown(scanner.dispose);
      await scanner.start();

      await expectLater(scanner.start(), throwsStateError);
    });
  });

  group('scanning', () {
    test('reports the payload of a frame that holds a QR', () async {
      final platform = _FakeCameraPlatform();
      final scanner = DesktopCameraScanner(platform: platform);
      addTearDown(scanner.dispose);
      await scanner.start();

      final seen = scanner.payloads.first;
      platform.frames.add(_frame('DD1.scanned'));

      expect(await seen, 'DD1.scanned');
    });

    test('a frame with no code produces nothing, and does not stop the scan',
        () async {
      final platform = _FakeCameraPlatform();
      final scanner = DesktopCameraScanner(platform: platform);
      addTearDown(scanner.dispose);
      await scanner.start();

      final seen = <String>[];
      scanner.payloads.listen(seen.add);

      // A blank frame, then a real one. The blank must be ignored
      // silently — at 12 fps most frames look like this.
      platform.frames.add(CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: null),
        planes: [
          CameraImagePlane(
            bytes: Uint8List(64 * 64 * 4)..fillRange(0, 64 * 64 * 4, 0xFF),
            bytesPerRow: 64 * 4,
          )
        ],
        width: 64,
        height: 64,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      platform.frames.add(_frame('DD1.after-blank'));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(seen, ['DD1.after-blank']);
    });

    test('does not filter repeated payloads', () async {
      // The sender repeats frames by design; deciding what is new is the
      // receiver's job. Filtering here would drop a legitimate repeat.
      final platform = _FakeCameraPlatform();
      final scanner = DesktopCameraScanner(platform: platform);
      addTearDown(scanner.dispose);
      await scanner.start();

      final seen = <String>[];
      scanner.payloads.listen(seen.add);

      for (var i = 0; i < 2; i++) {
        platform.frames.add(_frame('DD1.repeat'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }

      expect(seen, ['DD1.repeat', 'DD1.repeat']);
    });

    test('surfaces a camera that dies mid-scan', () async {
      final platform = _FakeCameraPlatform();
      final scanner = DesktopCameraScanner(platform: platform);
      addTearDown(scanner.dispose);
      await scanner.start();

      final error = scanner.payloads.first.then<Object?>((_) => null,
          onError: (Object e) => e);
      platform.frames.addError('unplugged');

      expect(await error, isA<DesktopCameraException>());
    });
  });

  group('dispose', () {
    test('releases the camera', () async {
      final platform = _FakeCameraPlatform();
      final scanner = DesktopCameraScanner(platform: platform);
      await scanner.start();

      await scanner.dispose();

      expect(platform.disposeCalls, 1);
      expect(scanner.cameraId, isNull);
    });

    test('is safe to call twice', () async {
      // A camera left open stays unavailable to every other application,
      // so dispose must never be the thing that throws.
      final platform = _FakeCameraPlatform();
      final scanner = DesktopCameraScanner(platform: platform);
      await scanner.start();

      await scanner.dispose();
      await scanner.dispose();

      expect(platform.disposeCalls, 1);
    });

    test('is safe when start never succeeded', () async {
      final scanner = DesktopCameraScanner(
        platform: _FakeCameraPlatform(cameras: const []),
      );
      await expectLater(scanner.start(), throwsA(isA<DesktopCameraException>()));

      await scanner.dispose();
    });
  });

  group('preview', () {
    test('refuses before start', () {
      final scanner = DesktopCameraScanner(platform: _FakeCameraPlatform());

      expect(scanner.preview, throwsStateError);
    });

    test('returns the platform widget once started', () async {
      final scanner = DesktopCameraScanner(platform: _FakeCameraPlatform());
      addTearDown(scanner.dispose);
      await scanner.start();

      expect(scanner.preview().key, const Key('preview'));
    });
  });

  group('aspect ratio and sensor rotation', () {
    test('an upright sensor reports its own ratio', () async {
      final scanner = DesktopCameraScanner(platform: _FakeCameraPlatform());
      addTearDown(scanner.dispose);
      await scanner.start();
      await Future<void>.delayed(Duration.zero);

      expect(scanner.aspectRatio, closeTo(640 / 480, 0.001));
    });

    test('a sideways sensor still reports the sensor ratio', () async {
      // Deliberately NOT rotated here. On Android buildPreview wraps the
      // texture in CameraX's RotatedPreviewDelegate, so the plugin has
      // already turned the image: rotating this figure too
      // double-corrected it and the preview came out stretched. The view
      // no longer computes a size from this value at all — it lets the
      // preview keep its own shape and scales it to cover.
      final scanner = DesktopCameraScanner(
        platform: _FakeCameraPlatform(cameras: const [
          CameraDescription(
            name: 'rear',
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 90,
          ),
        ]),
      );
      addTearDown(scanner.dispose);
      await scanner.start();
      await Future<void>.delayed(Duration.zero);

      expect(scanner.aspectRatio, closeTo(640 / 480, 0.001),
          reason: 'the platform rotates the preview; this is the sensor');
    });

    test('rotation does not change the measured resolution', () async {
      // suggestEmission reasons about how many pixels the camera
      // captures, which is a property of the sensor and not of how the
      // image is turned for display.
      final scanner = DesktopCameraScanner(
        platform: _FakeCameraPlatform(cameras: const [
          CameraDescription(
            name: 'rear',
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 270,
          ),
        ]),
      );
      addTearDown(scanner.dispose);
      await scanner.start();
      await Future<void>.delayed(Duration.zero);

      expect(scanner.capability?.width ?? 640, 640,
          reason: 'the sensor captured 640 wide however it is displayed');
    });
  });
}
