/// Tests for the desktop QR scanner's frame handling
/// (app/lib/src/desktop_scanner.dart).
///
/// The property worth pinning is the one that fails silently: **row
/// padding**. Capture backends align each row to a boundary, so a
/// 640-pixel BGRA row is usually 2560 bytes but can be more. Code that
/// assumes `width * bytesPerPixel` shears the image diagonally, and the
/// symptom is not a crash — it is a camera that simply never reads a
/// code, which looks like broken hardware.
///
/// These build frames with deliberate padding and check a real QR survives
/// the round trip.
library;

import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

import 'package:dead_drop/src/desktop_scanner.dart';

/// Renders [payload] as a QR code into a BGRA buffer.
///
/// [rowPadding] is extra bytes appended to each row, mimicking a capture
/// backend that aligns rows. Zero means a tightly packed buffer.
CameraImageData _bgraFrame(
  String payload, {
  int rowPadding = 0,
  int scale = 4,
  int quiet = 8,
}) {
  final qr = QrImage(QrCode.fromData(
    data: payload,
    errorCorrectLevel: QrErrorCorrectLevel.L,
  ));

  final side = (qr.moduleCount + quiet * 2) * scale;
  final stride = side * 4 + rowPadding;
  final bytes = Uint8List(stride * side);

  // White background, including the quiet zone a decoder needs.
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = 0xFF;
  }

  for (var row = 0; row < qr.moduleCount; row++) {
    for (var col = 0; col < qr.moduleCount; col++) {
      if (!qr.isDark(row, col)) continue;
      for (var dy = 0; dy < scale; dy++) {
        final y = (row + quiet) * scale + dy;
        for (var dx = 0; dx < scale; dx++) {
          final x = (col + quiet) * scale + dx;
          final i = y * stride + x * 4;
          bytes[i] = 0x00; // B
          bytes[i + 1] = 0x00; // G
          bytes[i + 2] = 0x00; // R
          bytes[i + 3] = 0xFF; // A
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

/// A frame shaped like what this app actually transmits.
const _realisticPayload =
    'DD1.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4v'
    'MDEyMzQ1Njc4OTo7PD0-P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFi'
    'Y2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn-AgYKDhIWGh4iJiouMjY6PkJGSk5SV';

void main() {
  group('frameToArgb', () {
    test('decodes a QR from a tightly packed BGRA frame', () {
      final frame = _bgraFrame('DD1.hello');
      final pixels = frameToArgb(frame);

      expect(pixels, isNotNull);
      expect(decodeArgb(pixels!, frame.width, frame.height), 'DD1.hello');
    });

    test('decodes a QR when rows are padded', () {
      // The regression this file exists for. 64 bytes of padding per row
      // is not exotic: 640x480 BGRA on a backend aligning to 64 bytes.
      final frame = _bgraFrame('DD1.hello', rowPadding: 64);
      final pixels = frameToArgb(frame);

      expect(pixels, isNotNull);
      expect(decodeArgb(pixels!, frame.width, frame.height), 'DD1.hello',
          reason: 'row padding must be read from bytesPerRow, not assumed '
              'to be width * 4 — getting this wrong shears the image and '
              'looks like a camera that never reads anything');
    });

    test('padding does not change the decoded pixels', () {
      // Stronger than "both decode": the two buffers describe the same
      // picture, so the extracted pixels must be identical.
      final packed = frameToArgb(_bgraFrame('DD1.hello'))!;
      final padded = frameToArgb(_bgraFrame('DD1.hello', rowPadding: 64))!;

      expect(padded.length, packed.length);
      expect(padded, orderedEquals(packed));
    });

    test('handles a payload the size of a real transfer frame', () {
      final frame = _bgraFrame(_realisticPayload, scale: 3);
      final pixels = frameToArgb(frame);

      expect(pixels, isNotNull);
      expect(decodeArgb(pixels!, frame.width, frame.height),
          _realisticPayload);
    });

    test('reads the luminance plane of a YUV420 frame', () {
      // Y alone is what a QR decoder needs; chroma carries nothing for a
      // black-and-white code.
      const w = 4, h = 2, stride = 6; // 2 bytes of padding per row
      final y = Uint8List(stride * h);
      for (var row = 0; row < h; row++) {
        for (var col = 0; col < w; col++) {
          y[row * stride + col] = row == 0 ? 0x00 : 0xFF;
        }
      }

      final pixels = frameToArgb(CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: null),
        planes: [CameraImagePlane(bytes: y, bytesPerRow: stride)],
        width: w,
        height: h,
      ));

      // Int32List stores signed ints, so an opaque pixel reads back
      // negative. Compare on the low 24 bits, which is the colour.
      expect(pixels, isNotNull);
      expect(pixels!.sublist(0, w).map((p) => p & 0xFFFFFF),
          everyElement(0x000000));
      expect(pixels.sublist(w).map((p) => p & 0xFFFFFF),
          everyElement(0xFFFFFF));
      expect(pixels.every((p) => (p >> 24) & 0xFF == 0xFF), isTrue,
          reason: 'every pixel must be fully opaque');
    });

    test('returns null for a format it does not understand', () {
      // Guessing would hide the real problem behind an intermittent
      // "no QR found".
      final pixels = frameToArgb(CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.jpeg, raw: null),
        planes: [CameraImagePlane(bytes: Uint8List(16), bytesPerRow: 4)],
        width: 2,
        height: 2,
      ));

      expect(pixels, isNull);
    });

    test('returns null for a frame with no planes', () {
      final pixels = frameToArgb(const CameraImageData(
        format: CameraImageFormat(ImageFormatGroup.bgra8888, raw: null),
        planes: [],
        width: 4,
        height: 4,
      ));

      expect(pixels, isNull);
    });

    test('returns null rather than reading past a short buffer', () {
      // A truncated frame is a real possibility mid-stream. It must not
      // throw a RangeError into the camera callback.
      final pixels = frameToArgb(CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: null),
        planes: [CameraImagePlane(bytes: Uint8List(8), bytesPerRow: 40)],
        width: 10,
        height: 10,
      ));

      expect(pixels, isNull);
    });
  });

  group('decodeArgb', () {
    test('returns null for a frame with no code, without throwing', () {
      // The common case at 12 fps: blurred, half-drawn, or between codes.
      final blank = Int32List(64 * 64)..fillRange(0, 64 * 64, 0xFFFFFFFF);

      expect(decodeArgb(blank, 64, 64), isNull);
    });

    test('returns null for noise', () {
      final noise = Int32List(64 * 64);
      for (var i = 0; i < noise.length; i++) {
        noise[i] = 0xFF000000 | ((i * 2654435761) & 0xFFFFFF);
      }

      expect(decodeArgb(noise, 64, 64), isNull);
    });
  });

  group('decodeFrame', () {
    test('goes from camera frame to payload in one call', () {
      expect(decodeFrame(_bgraFrame('DD1.endtoend', rowPadding: 32)),
          'DD1.endtoend');
    });

    test('returns null for an unusable frame', () {
      expect(
        decodeFrame(CameraImageData(
          format: const CameraImageFormat(ImageFormatGroup.nv21, raw: null),
          planes: [CameraImagePlane(bytes: Uint8List(4), bytesPerRow: 4)],
          width: 1,
          height: 1,
        )),
        isNull,
      );
    });
  });
}
