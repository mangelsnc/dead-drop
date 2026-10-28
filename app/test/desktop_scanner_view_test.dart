/// The camera preview must actually occupy the space it is given.
///
/// Reported from a phone, twice. First the preview was letterboxed:
/// AspectRatio inside Center fits the image, and a phone sensor is far
/// taller than the wide box it sits in, so the QR shrank to a band with
/// black above and below. The fix for that then broke it outright —
/// wrapping the preview in a FittedBox whose child was a 1px-tall
/// SizedBox left "a single white dot in the middle", because a camera
/// preview has no intrinsic size for a FittedBox to scale from.
///
/// These pin the property both attempts were reaching for: the preview
/// fills its box, at the camera's own ratio, with no collapsed axis.
library;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:dead_drop/src/desktop_camera.dart';
import 'package:dead_drop/ui/desktop_scanner_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reports a 640x480 camera and a preview widget the test can measure.
class _FakeCameraPlatform extends CameraPlatform {
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
      const Stream.empty();

  @override
  Widget buildPreview(int cameraId) =>
      Container(key: const Key('preview'), color: const Color(0xFF00FF00));

  @override
  Future<void> dispose(int cameraId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Size> previewSizeIn(WidgetTester tester, Size box) async {
    final scanner = DesktopCameraScanner(platform: _FakeCameraPlatform());
    addTearDown(scanner.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: box.width,
              height: box.height,
              child: DesktopScannerView(onDetect: (_) {}, scanner: scanner),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getSize(find.byKey(const Key('preview')));
  }

  testWidgets('the preview is not collapsed to nothing', (tester) async {
    final size = await previewSizeIn(tester, const Size(360, 300));

    expect(size.width, greaterThan(10),
        reason: 'a 1px preview is the "single white dot" that was reported');
    expect(size.height, greaterThan(10));
  });

  testWidgets('the preview covers a box wider than the camera',
      (tester) async {
    // 640x480 is 1.33; this box is 2.0, so width should match and height
    // overflow, leaving no empty band.
    const box = Size(600, 300);
    final size = await previewSizeIn(tester, box);

    expect(size.width, closeTo(box.width, 1),
        reason: 'anything narrower leaves a gap at the sides');
    expect(size.height, greaterThanOrEqualTo(box.height - 1),
        reason: 'letterboxing is what made the QR shrink on a phone');
  });

  testWidgets('the preview keeps the camera ratio rather than stretching',
      (tester) async {
    final size = await previewSizeIn(tester, const Size(600, 300));

    expect(size.width / size.height, closeTo(640 / 480, 0.02),
        reason: 'a squashed QR is harder to aim at');
  });
}
