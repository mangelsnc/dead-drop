/// The sending screen must not paint QR modules one rectangle at a time.
///
/// `QrImageView` issues one `canvas.drawRect` per module, and a 512-byte
/// chunk is a version 18 code: 7,921 rectangles. On the sending screen the
/// payload changes every frame, so that work is redone every frame — the
/// whole frame was measured at 132 ms on a MacBook Pro M3 and 547 ms on a
/// Slimbook running Kali, against 66 ms at 15 fps. The Slimbook managed
/// 1.8 of the 15 it was asked for.
///
/// `qr_raster.dart` renders each code to an image instead, and the frame
/// carries one `drawImageRect`. This holds the send page to that: a
/// revert to `QrImageView` there brings the cost straight back, and
/// nothing else in the test suite would notice.
///
/// The receive page still uses `QrImageView`, and should: its handshake
/// code is drawn once and then sits there.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `send_page.dart` with comments stripped, so that a comment naming the
/// widget cannot satisfy — or break — a check about the code.
String _sendPageCode() {
  final source = File('lib/ui/send/send_page.dart').readAsStringSync();
  return source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
}

void main() {
  test('the send page does not build a QrImageView', () {
    expect(_sendPageCode(), isNot(contains('QrImageView(')),
        reason: 'the sending screen draws a code every frame, and '
            'QrImageView redraws 7,921 rectangles each time. Use the '
            'rasteriser in qr_raster.dart.');
  });

  test('the send page uses the rasteriser', () {
    // The other half: the check above also passes if the QR stopped
    // being drawn at all.
    final code = _sendPageCode();
    expect(code, contains('QrRasteriser('),
        reason: 'the send page must build a rasteriser');
    expect(code, contains('drawImageRect'),
        reason: 'and draw its output as one image');
  });

  test('the receive page may still use QrImageView', () {
    // Not a prohibition in the wrong direction: the handshake code is
    // drawn once and does not change, so per-module painting costs
    // nothing there. Pinned so that a well-meant sweep of the codebase
    // does not churn it for symmetry.
    final receive = File('lib/ui/receive/receive_page.dart').readAsStringSync();
    expect(receive, contains('QrImageView('),
        reason: 'the handshake QR is static; converting it would add a '
            'rasteriser and an image lifecycle for no gain');
  });
}
