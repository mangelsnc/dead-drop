/// The progress bar rises steadily and does not sit at its cap.
///
/// Two failures reported from devices, in that order. First "24 of
/// 2137 chunks" after a thousand codes, which read as 1% when the
/// transfer was nearly half done. Then, after counting pending frames
/// to fix that, two or three minutes stuck on the final 1%.
///
/// Both come from measuring the wrong thing. Chunks resolved
/// understates, because belief propagation reveals nothing until it
/// cascades; chunks covered by pending frames overstates, because
/// frames touch nearly every chunk long before they can be resolved.
/// Frames received against frames expected is the quantity that
/// actually tracks the work.
library;

import 'dart:typed_data';

import 'package:dead_drop/src/fountain.dart';
import 'package:flutter_test/flutter_test.dart';

List<Uint8List> _chunks(int k) => List.generate(k, (i) {
      final b = Uint8List(32);
      b[0] = i & 0xff;
      b[1] = (i >> 8) & 0xff;
      return b;
    });

/// Runs a transfer, reading one frame in [readOneIn], and reports the
/// progress seen after each frame.
List<double> _run(int k, {int readOneIn = 1, int seed = 4242}) {
  final enc = LTEncoder(_chunks(k));
  final dec = LTDecoder(k: k, chunkSize: 32);
  final seen = <double>[];
  for (var seq = 1; seq <= k * 300 && !dec.done; seq++) {
    if (seq % readOneIn != 0) continue;
    final (ids, payload) = enc.makeFrame(seq, seed);
    dec.addFrame(ids, payload);
    seen.add(dec.progress);
  }
  return seen;
}

void main() {
  group('LTDecoder.progress', () {
    test('is zero before anything arrives', () {
      expect(LTDecoder(k: 100, chunkSize: 32).progress, 0);
    });

    test('rises steadily rather than jumping at the end', () {
      // The first failure: resolved chunks stay near zero for most of a
      // transfer, so a bar driven by them says 1% when half the work is
      // done.
      final seen = _run(2048);
      final quarter = seen[seen.length ~/ 4];
      final half = seen[seen.length ~/ 2];
      final threeQuarters = seen[seen.length * 3 ~/ 4];

      expect(quarter, closeTo(0.25, 0.1));
      expect(half, closeTo(0.5, 0.1));
      expect(threeQuarters, closeTo(0.75, 0.1));
    });

    test('does not sit at its cap for a meaningful part of the run', () {
      // The second failure, which is what "stuck on the last 1%" was.
      // Tested lossy as well as clean, because that is the case where
      // the old measure was worst.
      for (final readOneIn in [1, 4, 8]) {
        final seen = _run(200, readOneIn: readOneIn);
        final atCap = seen.where((p) => p >= 0.99).length;
        expect(
          atCap / seen.length,
          lessThan(0.15),
          reason: 'reading 1 frame in $readOneIn, the bar sat at its cap '
              'for ${(atCap / seen.length * 100).round()}% of the transfer',
        );
      }
    });

    test('a bar driven by resolved chunks would have failed that', () {
      // The control. Without it the tests above could pass for a
      // measure that happens to be smooth but means nothing.
      const k = 2048;
      final enc = LTEncoder(_chunks(k));
      final dec = LTDecoder(k: k, chunkSize: 32);
      for (var seq = 1; seq <= 1024; seq++) {
        final (ids, payload) = enc.makeFrame(seq, 4242);
        dec.addFrame(ids, payload);
      }
      expect(dec.decoded.length / k, lessThan(0.05),
          reason: 'resolved chunks really are near zero at the half way '
              'point, which is what made the first bar useless');
      expect(dec.progress, greaterThan(0.3));
    });

    test('reaches exactly 1 when the transfer finishes, and not before',
        () {
      const k = 200;
      final enc = LTEncoder(_chunks(k));
      final dec = LTDecoder(k: k, chunkSize: 32);
      for (var seq = 1; seq <= k * 20; seq++) {
        final (ids, payload) = enc.makeFrame(seq, 7);
        dec.addFrame(ids, payload);
        if (dec.done) break;
        expect(dec.progress, lessThan(1.0),
            reason: 'the bar must not fill while chunks are missing');
      }
      expect(dec.done, isTrue);
      expect(dec.progress, 1.0);
    });

    test('never goes backwards', () {
      // A bar that retreats reads as a failure.
      final seen = _run(300, seed: 1234);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]),
            reason: 'progress fell at frame $i');
      }
    });

    test('never exceeds 1, however many frames arrive', () {
      const k = 50;
      final enc = LTEncoder(_chunks(k));
      final dec = LTDecoder(k: k, chunkSize: 32);
      for (var seq = 1; seq <= k * 30; seq++) {
        final (ids, payload) = enc.makeFrame(seq, 99);
        dec.addFrame(ids, payload);
        expect(dec.progress, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
