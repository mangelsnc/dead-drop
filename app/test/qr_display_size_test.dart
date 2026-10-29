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
    test('fills the width it is given', () {
      expect(qrDisplaySize(500), 500 - 32);
      expect(qrDisplaySize(600), 600 - 32);
    });

    test('never draws smaller than the old fixed size', () {
      expect(qrDisplaySize(100), kQrMinDisplaySize);
      expect(qrDisplaySize(0), kQrMinDisplaySize);
    });

    test('stops growing past what fits in a camera frame', () {
      expect(qrDisplaySize(4000), kQrMaxDisplaySize);
    });

    test('an unbounded width falls back to the floor rather than infinity',
        () {
      expect(qrDisplaySize(double.infinity), kQrMinDisplaySize);
      expect(qrDisplaySize(double.infinity).isFinite, isTrue);
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
      final size = qrDisplaySize(phoneWidth);

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
      expect(qrDisplaySize(phoneWidth) / modules, lessThan(3.0));
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
