import 'package:dead_drop/ui/send/send_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

/// The module count of the code a chunk of [bytes] produces, at the error
/// correction level that chunk size is usable at.
int _moduleCountFor(int bytes, int ecLevel) {
  // A frame is the payload base64-encoded behind a short header, which is
  // what the emitter puts on screen.
  final payload = 'DD1:${'A' * ((bytes * 4 / 3).ceil() + 24)}';
  return QrImage(QrCode.fromData(data: payload, errorCorrectLevel: ecLevel))
      .moduleCount;
}

void main() {
  group('qrDisplaySize', () {
    test('fills the space it is given', () {
      expect(qrDisplaySize(500, 2000), 500 - 32);
      expect(qrDisplaySize(2000, 500), 500 - 32);
    });

    test('is limited by height as well as width', () {
      // A wide, short window. Sizing on width alone drew a code taller
      // than its box, and the frame counter and buttons below it were
      // painted over the modules -- corrupting the code the camera
      // reads. Reported from macOS.
      expect(qrDisplaySize(1400, 420), 420 - 32);
      expect(qrDisplaySize(1400, 420), lessThan(qrDisplaySize(1400, 2000)));
    });

    test('never asks for more room than it was given', () {
      // The overflow property itself, over the whole range rather than
      // at the sizes that happened to be reported.
      for (final w in [120.0, 320.0, 411.0, 800.0, 1400.0, 4000.0]) {
        for (final h in [60.0, 200.0, 420.0, 900.0, 2000.0]) {
          final size = qrDisplaySize(w, h);
          expect(size, lessThanOrEqualTo(w), reason: '${w}x$h');
          expect(size, lessThanOrEqualTo(h), reason: '${w}x$h');
        }
      }
    });

    test('stops growing past what fits in a camera frame', () {
      expect(qrDisplaySize(4000, 4000), kQrMaxDisplaySize);
    });

    test('never returns a negative size', () {
      for (final h in [0.0, 10.0, 32.0]) {
        expect(qrDisplaySize(1400, h), greaterThanOrEqualTo(0));
      }
    });

    test('unbounded constraints produce nothing rather than infinity', () {
      // An unbounded box cannot say how much room there is, and a code
      // sized to infinity would crash the layout.
      expect(qrDisplaySize(double.infinity, double.infinity), 0);
      expect(qrDisplaySize(double.infinity, 500).isFinite, isTrue);
    });

    test('256 and 512 byte chunks clear three pixels per module on a '
        'phone-width screen', () {
      // Three samples per module is what a decoder needs; below two it
      // cannot work at all. This is the sender's own rasterisation, and
      // the camera reduces the code again on top of it, so the bar here
      // is the full three rather than the bare floor.
      //
      // 392 is a 411-pixel-wide phone (the Redmi Note 14 this was
      // reported from) less the page's own horizontal padding.
      const phoneWidth = 392.0;
      final size = qrDisplaySize(phoneWidth, 2000);

      for (final chunk in [256, 512]) {
        final modules = _moduleCountFor(chunk, QrErrorCorrectLevel.M);
        final perModule = size / modules;
        expect(
          perModule,
          greaterThanOrEqualTo(3.0),
          reason: 'a $chunk-byte chunk is $modules modules, drawn at '
              '${size.toStringAsFixed(0)} px: '
              '${perModule.toStringAsFixed(2)} px per module',
        );
      }
    });

    test('a 1024-byte chunk cannot reach that bar on a phone at all', () {
      // Not a gap in the sizing: 1024 bytes is a 141-module code, and a
      // phone-width screen has no room to draw it at three pixels per
      // module however the layout is arranged. Recorded here so that a
      // later change claiming to fix scanning at 1024 on a phone has to
      // confront the arithmetic rather than pass by accident.
      const phoneWidth = 392.0;
      final modules = _moduleCountFor(1024, QrErrorCorrectLevel.M);
      expect(qrDisplaySize(phoneWidth, 2000) / modules, lessThan(3.0));
      expect(modules * 3, greaterThan(phoneWidth));
    });

    test('the old fixed 300 px would have failed that bar', () {
      // Without this the test above passes for the wrong reason: it would
      // hold at any size, and prove nothing about the change. 300 is what
      // the renderer was fixed at before.
      final modules = _moduleCountFor(1024, QrErrorCorrectLevel.M);
      expect(300 / modules, lessThan(3.0));
    });
  });
}
