/// Does rasterising a QR once beat drawing its modules every frame, and
/// does it stay honest about which payload it rendered?
///
/// The sending screen's frame was measured at 132 ms on a MacBook Pro M3
/// and 547 ms on a Slimbook running Kali, against a 66 ms budget at
/// 15 fps. `QrPainter` issues one `canvas.drawRect` per module, and a
/// 512-byte chunk is a version 18 code: 89×89 = 7,921 rectangles, rebuilt
/// from scratch on every frame because the payload changes.
///
/// `QrRasteriser` renders each code to an image ahead of its turn, so the
/// frame carries one `drawImage` instead.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:dead_drop/src/qr_raster.dart';

/// A payload the size of a real 512-byte chunk once encoded.
String _chunkPayload(int n) => 'DD1.${'A' * 700}$n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rendering', () {
    test('produces an image at the size asked for', () async {
      final r = QrRasteriser(errorCorrectionLevel: QrErrorCorrectLevel.L);
      final out = await r.rasterise(_chunkPayload(0), 320);

      expect(out, isNotNull);
      addTearDown(out!.dispose);
      expect(out.image.width, 320);
      expect(out.image.height, 320);
      expect(out.sizePx, 320);
    });

    test('carries the payload it rendered', () async {
      // The display compares this against what it was asked to show. A
      // rasteriser that forgot, or lied, would let a stale code stay on
      // screen while the receiver waits for the next one.
      final r = QrRasteriser(errorCorrectionLevel: QrErrorCorrectLevel.L);
      final payload = _chunkPayload(7);
      final out = await r.rasterise(payload, 160);

      addTearDown(out!.dispose);
      expect(out.payload, payload);
    });

    test('a zero or negative size renders nothing', () async {
      // The layout reports a size of zero before the first frame is laid
      // out, and ui.Picture.toImage throws on it.
      final r = QrRasteriser(errorCorrectionLevel: QrErrorCorrectLevel.L);

      expect(await r.rasterise(_chunkPayload(0), 0), isNull);
      expect(await r.rasterise(_chunkPayload(0), -10), isNull);
    });

    test('a payload too long for any version renders nothing', () async {
      // Rather than throwing into the emission timer. The spec caps chunk
      // sizes so this should not arise, but a hint from another device
      // decides part of the payload size.
      final r = QrRasteriser(errorCorrectionLevel: QrErrorCorrectLevel.H);
      final tooLong = 'D' * 5000;

      expect(await r.rasterise(tooLong, 320), isNull);
    });
  });

  group('the version is found once', () {
    test('the first payload pins it', () async {
      final r = QrRasteriser(errorCorrectionLevel: QrErrorCorrectLevel.L);
      expect(r.pinnedVersion, isNull);

      final out = await r.rasterise(_chunkPayload(0), 160);
      addTearDown(out!.dispose);

      expect(r.pinnedVersion, isNotNull);
      expect(r.pinnedVersion, greaterThan(0));
    });

    test('later payloads of the same size reuse it', () async {
      // The saving this exists for: QrVersions.auto costs 2.38 ms per
      // frame against 0.007 ms when the version is given, and every
      // frame of a transfer carries the same chunk size.
      final r = QrRasteriser(errorCorrectionLevel: QrErrorCorrectLevel.L);
      final first = await r.rasterise(_chunkPayload(0), 160);
      addTearDown(first!.dispose);
      final pinned = r.pinnedVersion;

      for (var i = 1; i < 5; i++) {
        final out = await r.rasterise(_chunkPayload(i), 160);
        addTearDown(out!.dispose);
      }

      expect(r.pinnedVersion, pinned);
      expect(r.versionMisses, 0,
          reason: 'payloads of one size must all fit one version, or the '
              'pinning is unsound');
    });

    test('a payload that outgrows the pinned version still renders',
        () async {
      // A bootstrap code and a data code need not be the same length.
      // Failing here would stop the transfer dead; searching again costs
      // one frame's worth of version search.
      final r = QrRasteriser(errorCorrectionLevel: QrErrorCorrectLevel.L);
      final small = await r.rasterise('DD1.short', 160);
      addTearDown(small!.dispose);
      final smallVersion = r.pinnedVersion!;

      final big = await r.rasterise(_chunkPayload(0), 160);

      expect(big, isNotNull, reason: 'the larger payload must still render');
      addTearDown(big!.dispose);
      expect(r.versionMisses, 1,
          reason: 'the miss is counted, not silently absorbed');
      expect(r.pinnedVersion, greaterThan(smallVersion));
    });
  });

  test('drawing the image beats drawing the modules', () async {
    // The whole justification, held as a test so that a change which
    // quietly reverts to per-module painting fails here.
    //
    // A ratio, not an absolute: this runs in a software renderer on an
    // emulated CPU, where no absolute figure means anything about real
    // hardware. The ratio measured when this was written was about 73×;
    // the threshold below is deliberately far looser, so the test
    // reports a lost optimisation rather than ordinary noise.
    const size = 400;
    final payloads = [for (var i = 0; i < 10; i++) _chunkPayload(i)];

    final version = QrValidator.validate(
      data: payloads.first,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.L,
    ).qrCode!.typeNumber;

    // Per-module painting, as QrImageView does it.
    final modules = Stopwatch()..start();
    for (final payload in payloads) {
      final qr = QrValidator.validate(
        data: payload,
        version: version,
        errorCorrectionLevel: QrErrorCorrectLevel.L,
      ).qrCode!;
      final recorder = ui.PictureRecorder();
      QrPainter.withQr(qr: qr, gapless: true)
          .paint(Canvas(recorder), const Size(size * 1.0, size * 1.0));
      recorder.endRecording().dispose();
    }
    modules.stop();

    // Drawing one already-rasterised image.
    final r = QrRasteriser(errorCorrectionLevel: QrErrorCorrectLevel.L);
    final ready = await r.rasterise(payloads.first, size);
    addTearDown(ready!.dispose);

    final blit = Stopwatch()..start();
    for (var i = 0; i < payloads.length; i++) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImage(ready.image, Offset.zero, Paint());
      recorder.endRecording().dispose();
    }
    blit.stop();

    expect(blit.elapsedMicroseconds * 5, lessThan(modules.elapsedMicroseconds),
        reason: 'drawing a ready image took '
            '${blit.elapsedMicroseconds}us against '
            '${modules.elapsedMicroseconds}us for the modules, a ratio of '
            '${(modules.elapsedMicroseconds / blit.elapsedMicroseconds)
                .toStringAsFixed(1)}x. Below 5x the rasterisation is not '
            'earning the complexity it costs.');
  });
}
