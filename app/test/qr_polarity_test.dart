/// Can the decoder read a code this screen did not draw in plain black
/// on plain white?
///
/// Two questions, both raised by a transfer that failed on real hardware:
/// a Redmi Note 14 emitting to a Logitech StreamCam, where the phone's
/// screen was bright enough that the webcam's auto-exposure closed down
/// and the code's dark modules washed out to grey.
///
/// The first is inversion — light modules on a dark field. A QR drawn
/// that way emits far less light, so a camera metering the scene is not
/// driven to stop down. The QR standard assumes dark-on-light, and
/// whether a given decoder also accepts the opposite is a property of
/// its binarizer, not of the format. This project's binarizer is
/// GlobalHistogramBinarizer (see decodeArgb in desktop_scanner.dart), so
/// the answer has to be measured here rather than assumed.
///
/// The second is a warmer white. Cutting the emitted light by dimming
/// the light modules costs contrast, and contrast is what the binarizer
/// has to work with. These pin where that trade stops working.
///
/// Nothing here is a claim about what a real camera does with a real
/// screen — only about what the decoder accepts once the frame reaches
/// it. A frame built in memory has no glare, no focus and no sensor
/// noise.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

import 'package:dead_drop/src/desktop_scanner.dart';

/// Renders [payload] as a QR with [dark] and [light] module colours, each
/// an ARGB value, and returns the pixels as the decoder receives them.
///
/// [light] paints the quiet zone too: a code's margin is part of the code,
/// and inverting one without the other produces something no decoder is
/// required to read.
Int32List _render(
  String payload, {
  required int dark,
  required int light,
  int scale = 4,
  int quiet = 8,
}) {
  final qr = QrImage(QrCode.fromData(
    data: payload,
    errorCorrectLevel: QrErrorCorrectLevel.L,
  ));
  final side = (qr.moduleCount + quiet * 2) * scale;
  final pixels = Int32List(side * side)..fillRange(0, side * side, light);

  for (var row = 0; row < qr.moduleCount; row++) {
    for (var col = 0; col < qr.moduleCount; col++) {
      if (!qr.isDark(row, col)) continue;
      for (var dy = 0; dy < scale; dy++) {
        for (var dx = 0; dx < scale; dx++) {
          final y = (row + quiet) * scale + dy;
          final x = (col + quiet) * scale + dx;
          pixels[y * side + x] = dark;
        }
      }
    }
  }
  return pixels;
}

/// The side length [_render] produces for [payload], so the decoder can be
/// told the frame's shape.
int _sideFor(String payload, {int scale = 4, int quiet = 8}) {
  final qr = QrImage(QrCode.fromData(
    data: payload,
    errorCorrectLevel: QrErrorCorrectLevel.L,
  ));
  return (qr.moduleCount + quiet * 2) * scale;
}

const _black = 0xFF000000;
const _white = 0xFFFFFFFF;

/// A payload the length of a real frame, so these measure the codes this
/// app actually emits rather than a toy string. 512 bytes base64-ish is
/// roughly 700 characters, which is what the device tests ran at.
final _payload = 'DD1.${'A1b2C3d4' * 88}';

void main() {
  String? decode(Int32List pixels, String payload) =>
      decodeArgb(pixels, _sideFor(payload), _sideFor(payload));

  group('polarity', () {
    test('the ordinary code, dark on white, reads', () {
      // The control. Without it a failure below could mean the harness is
      // wrong rather than the colours.
      final pixels = _render(_payload, dark: _black, light: _white);

      expect(decode(pixels, _payload), _payload);
    });

    test('an inverted code, light on dark, does NOT read', () {
      // Measured, against the hope that it would. An inverted code emits
      // far less light, which is exactly what the StreamCam failure
      // called for — but this decoder will not read one. zxing2's
      // QRCodeReader over GlobalHistogramBinarizer does not try the
      // opposite polarity, and swept across dark fields from pure black
      // to mid grey (0x00, 0x20, 0x40, 0x80) not one decoded.
      //
      // This test exists to stop the idea being revived cheaply: if a
      // future decoder change makes inversion work, this fails and the
      // option reopens.
      for (final field in [0xFF000000, 0xFF202020, 0xFF404040, 0xFF808080]) {
        final pixels = _render(_payload, dark: _white, light: field);

        expect(decode(pixels, _payload), isNull,
            reason: 'inversion decoded against field '
                '0x${field.toRadixString(16)} — the option is open again');
      }
    });
  });

  group('a warmer, dimmer light module', () {
    // Candidates from warm white down to a deep cream. The point is not
    // the hue — a camera binarizes by luminance, so hue barely matters —
    // but how much light the bright modules give off. Each entry carries
    // its approximate relative luminance against pure white.
    const creams = <String, int>{
      'warm white  (#FFF8E7, ~97%)': 0xFFFFF8E7,
      'cream       (#F5E6C8, ~90%)': 0xFFF5E6C8,
      'deep cream  (#E8D5A3, ~83%)': 0xFFE8D5A3,
      'amber tint  (#D9BE7A, ~74%)': 0xFFD9BE7A,
    };

    for (final entry in creams.entries) {
      test('${entry.key} still reads against black', () {
        final pixels = _render(_payload, dark: _black, light: entry.value);

        expect(decode(pixels, _payload), _payload,
            reason: '${entry.key} lost too much contrast to decode');
      });
    }

    test('the decoder tolerates far more dimming than a screen needs', () {
      // Swept: the light module can fall to 0x20 (about 12% of white)
      // and still decode; 0x10 does not. Every cream above is an order
      // of magnitude clear of that floor.
      //
      // The point is what this does NOT prove. The decoder is not the
      // constraint on how warm or dim the light modules may be, so a
      // test that only shows creams decoding says nothing about whether
      // one helps. What a warmer white is for is the camera: less
      // emitted light means auto-exposure does not stop down and crush
      // the dark modules, which is what failed against a webcam. That
      // is a property of a real screen and a real sensor, and no frame
      // built in memory can measure it.
      final justAbove = _render(_payload, dark: _black, light: 0xFF202020);
      final justBelow = _render(_payload, dark: _black, light: 0xFF101010);

      expect(decode(justAbove, _payload), _payload);
      expect(decode(justBelow, _payload), isNull);
    });
  });

  group('where it stops working', () {
    // A test that only ever passes proves the decoder is permissive, not
    // that these colours are safe. These pin the far side: colour pairs
    // the decoder must NOT read, so a change that silently flattened the
    // contrast would fail here.
    test('below the measured floor, nothing reads', () {
      // 0x10 against black. This started out asserting that 0x3A failed,
      // which was a guess, and it decoded fine — the binarizer
      // normalises by histogram, so what matters is the separation
      // between the two peaks, not the absolute brightness. The floor
      // was then swept for rather than assumed.
      final pixels = _render(_payload, dark: _black, light: 0xFF101010);

      expect(decode(pixels, _payload), isNull,
          reason: 'if this reads, the floor moved and the creams above '
              'are no longer bounded by anything');
    });

    test('no contrast at all does not read', () {
      final pixels = _render(_payload, dark: _white, light: _white);

      expect(decode(pixels, _payload), isNull);
    });
  });
}
