/// desktop_scanner.dart — reading QR codes from a camera on Linux and
/// Windows, where `mobile_scanner` has no implementation.
///
/// The scanner this app uses elsewhere ships android, ios, macos and web
/// only. The request for Linux has sat unanswered since 2022, so the
/// desktop builds get their scanner from two smaller pieces: camera capture
/// from `camera_desktop`, and decoding from `zxing2` in pure Dart.
///
/// **Why not a packaged combination.** `flutter_zxing` does both in one
/// dependency, but pulls `image_picker` → `file_selector` → `http`: a
/// network client in the dependency graph of an app whose central claim is
/// that it contains no network code. Four small packages are a better
/// trade than twenty and that.
///
/// **Why pure Dart decoding is fast enough.** Measured on this project's
/// own frames — a 704-character `DD1.` payload rendered at 640x480 —
/// `zxing2` decodes in 5.3 ms median, 7.8 ms at p95, against the 83 ms
/// available per frame at 12 fps. The decode runs on a background isolate
/// anyway, so even a slow frame cannot stutter the preview.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:zxing2/qrcode.dart';

/// Whether this platform can scan a QR code from a camera at all.
///
/// Two different implementations sit behind one answer: `mobile_scanner`
/// on android, ios and macos, and the camera_desktop + zxing2 pair in
/// this library on linux and windows. The UI should ask this rather than
/// test the platform itself, so adding a platform is one edit here.
bool get canScanQr =>
    Platform.isAndroid ||
    Platform.isIOS ||
    Platform.isMacOS ||
    Platform.isLinux ||
    Platform.isWindows;

/// Whether this platform scans through the camera-plus-zxing2 path.
///
/// Every platform now does. It used to be Linux and Windows only, with
/// `mobile_scanner` elsewhere — but that package decodes with Google's
/// ML Kit, which drags Play Services and the datatransport telemetry
/// stack into the APK and with them `android.permission.INTERNET`. An app
/// whose central claim is that it makes no network calls cannot ship a
/// binary that asks for network permission; a reviewer who unzips the APK
/// finds the opposite of what the submission says.
///
/// The replacement was already here: the `camera` plugin family provides
/// frames on every platform through one interface, and this library
/// decodes them in pure Dart. Kept as a getter rather than inlined so the
/// routing stays in one place if a platform ever needs its own path again.
bool get usesDesktopScanner => true;

/// Converts one camera frame to the ARGB pixel array `zxing2` expects.
///
/// Returns null for a frame whose format this does not understand, rather
/// than guessing: a mis-read frame decodes to nothing anyway, and guessing
/// would hide the real problem behind an intermittent "no QR found".
///
/// **Rows are read using `bytesPerRow`, never `width * bytesPerPixel`.**
/// Capture backends pad each row to an alignment boundary, so a 640-pixel
/// BGRA row is often 2560 bytes but can be more. Assuming the unpadded
/// width shears the image diagonally, and the failure looks like a camera
/// that simply never reads a code.
Int32List? frameToArgb(CameraImageData frame) {
  if (frame.planes.isEmpty) return null;

  final plane = frame.planes.first;
  final width = frame.width;
  final height = frame.height;
  final stride = plane.bytesPerRow;
  final bytes = plane.bytes;

  final out = Int32List(width * height);

  switch (frame.format.group) {
    // What camera_desktop delivers on Linux and Windows.
    case ImageFormatGroup.bgra8888:
      for (var y = 0; y < height; y++) {
        var src = y * stride;
        var dst = y * width;
        for (var x = 0; x < width; x++, src += 4, dst++) {
          if (src + 3 >= bytes.length) return null;
          final b = bytes[src], g = bytes[src + 1], r = bytes[src + 2];
          out[dst] = 0xFF000000 | (r << 16) | (g << 8) | b;
        }
      }
      return out;

    // YUV420: the luminance plane alone is what a QR decoder needs, and
    // chroma carries nothing for a black-and-white code. Treating Y as
    // grey keeps this cheap — no colour conversion per pixel.
    case ImageFormatGroup.yuv420:
      for (var y = 0; y < height; y++) {
        var src = y * stride;
        var dst = y * width;
        for (var x = 0; x < width; x++, src++, dst++) {
          if (src >= bytes.length) return null;
          final v = bytes[src];
          out[dst] = 0xFF000000 | (v << 16) | (v << 8) | v;
        }
      }
      return out;

    default:
      return null;
  }
}

/// Decodes a QR code from an ARGB pixel array, or returns null when the
/// frame holds none.
///
/// A frame with no readable code is the normal case, not an error: at
/// 12 fps most frames are blurred, half-drawn, or between codes. This
/// returns null for all of them and never throws, so the caller can treat
/// every frame identically.
String? decodeArgb(Int32List pixels, int width, int height) {
  try {
    final bitmap = BinaryBitmap(
      GlobalHistogramBinarizer(RGBLuminanceSource(width, height, pixels)),
    );
    return QRCodeReader().decode(bitmap).text;
  } catch (_) {
    // NotFoundException, FormatException, ChecksumException — all mean
    // "no usable code in this frame", which is routine here.
    return null;
  }
}

/// Decodes one camera frame, or returns null.
///
/// Shaped to run inside `compute()`: one argument, one result, no captured
/// state. See [DesktopScannerIsolate].
String? decodeFrame(CameraImageData frame) {
  final pixels = frameToArgb(frame);
  if (pixels == null) return null;
  return decodeArgb(pixels, frame.width, frame.height);
}
