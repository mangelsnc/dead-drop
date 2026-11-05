import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:dead_drop/src/chunking.dart';
import 'package:dead_drop/src/desktop_camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

int _moduleCountFor(int chunkBytes, int ecLevel) {
  const frameOverhead = 48;
  final chars = (chunkBytes * 4 / 3).ceil() + frameOverhead;
  return QrImage(
    QrCode.fromData(data: 'A' * chars, errorCorrectLevel: ecLevel),
  ).moduleCount;
}

void main() {
  group('capture resolution', () {
    test('every platform but Linux captures at high', () {
      for (final os in ['macos', 'windows', 'android', 'ios']) {
        expect(resolutionPresetFor(os), ResolutionPreset.high, reason: os);
      }
    });

    test('Linux is held at medium', () {
      // camera_linux can fail to initialise above medium, and a scanner
      // that will not start is worse than one needing a steadier hand.
      expect(resolutionPresetFor('linux'), ResolutionPreset.medium);
    });

    test('no platform captures at low', () {
      // low is 320x240. A macOS receiver ran at that and read nothing
      // from a phone at any distance: backing away to fit the code in
      // frame only made each module smaller.
      for (final os in ['macos', 'windows', 'linux', 'android', 'ios']) {
        expect(resolutionPresetFor(os), isNot(ResolutionPreset.low),
            reason: os);
      }
    });

    test('low could not have resolved even the sparsest code we emit', () {
      // The control for the test above: without it, that test would pass
      // for any preset at all and prove nothing about whether the one
      // chosen is sufficient.
      final sparsest = _moduleCountFor(
        kChunkSizeOptions.first,
        QrErrorCorrectLevel.M,
      );
      expect(
        pixelsPerModule(
          captureWidth: kPresetCaptureWidth[ResolutionPreset.low]!,
          moduleCount: sparsest,
        ),
        lessThan(3.0),
      );
    });

    test('the chosen resolution resolves the chunk sizes it must', () {
      // 512 bytes is the size that has to work: it is what the app
      // recommends for a file of any size, and 1024 is already known not
      // to fit on a phone-width sender screen.
      for (final os in ['macos', 'windows', 'linux']) {
        final width = kPresetCaptureWidth[resolutionPresetFor(os)]!;
        for (final chunk in [256, 512]) {
          final modules = _moduleCountFor(chunk, QrErrorCorrectLevel.M);
          expect(
            pixelsPerModule(captureWidth: width, moduleCount: modules),
            greaterThanOrEqualTo(3.0),
            reason: '$os at ${width}px, $chunk-byte chunk '
                '($modules modules)',
          );
        }
      }
    });

    test('pixelsPerModule falls as the code gets denser', () {
      // The relationship the whole diagnosis rests on. If this ever
      // inverts, the arithmetic above is measuring nothing.
      final sparse = pixelsPerModule(captureWidth: 1280, moduleCount: 77);
      final dense = pixelsPerModule(captureWidth: 1280, moduleCount: 141);
      expect(dense, lessThan(sparse));
    });

    test('pixelsPerModule rises with capture width', () {
      expect(
        pixelsPerModule(captureWidth: 1280, moduleCount: 105),
        greaterThan(pixelsPerModule(captureWidth: 320, moduleCount: 105)),
      );
    });
  });
}
