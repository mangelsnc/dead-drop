/// Progress reflects the work done, not just the chunks revealed.
///
/// Reported from a device: a 1 MB transfer sat at "24 of 2137 chunks"
/// after a thousand codes and looked stalled. It was not — belief
/// propagation reveals almost nothing until it cascades. Counting only
/// resolved chunks told the user the transfer was 1% done when it was
/// nearly half way, which is the difference between waiting and giving
/// up.
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

void main() {
  group('LTDecoder.progress', () {
    test('is zero before anything arrives', () {
      expect(LTDecoder(k: 100, chunkSize: 32).progress, 0);
    });

    test('rises long before any chunk is resolved', () {
      // The whole point. Partway through a large transfer the resolved
      // count is still near zero while most of the work is done.
      const k = 2048;
      final enc = LTEncoder(_chunks(k));
      final dec = LTDecoder(k: k, chunkSize: 32);
      for (var seq = 1; seq <= 1024; seq++) {
        final (ids, payload) = enc.makeFrame(seq, 4242);
        dec.addFrame(ids, payload);
      }

      final naive = dec.decoded.length / k;
      expect(naive, lessThan(0.05),
          reason: 'the old measure really did read near zero here');
      expect(dec.progress, greaterThan(0.4),
          reason: 'half the frames are in, so the bar must show it');
    });

    test('reaches exactly 1 when the transfer finishes, and not before', () {
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

    test('never exceeds 1, even when more frames arrive than needed', () {
      // pending can hold far more frames than there are chunks.
      const k = 50;
      final enc = LTEncoder(_chunks(k));
      final dec = LTDecoder(k: k, chunkSize: 32);
      for (var seq = 1; seq <= k * 30; seq++) {
        final (ids, payload) = enc.makeFrame(seq, 99);
        dec.addFrame(ids, payload);
        expect(dec.progress, inInclusiveRange(0.0, 1.0),
            reason: 'at seq $seq');
      }
    });

    test('never goes backwards', () {
      // pending shrinks as frames are peeled, so a naive sum of decoded
      // and pending could fall. A bar that retreats reads as a failure.
      const k = 300;
      final enc = LTEncoder(_chunks(k));
      final dec = LTDecoder(k: k, chunkSize: 32);
      var previous = 0.0;
      for (var seq = 1; seq <= k * 10 && !dec.done; seq++) {
        final (ids, payload) = enc.makeFrame(seq, 1234);
        dec.addFrame(ids, payload);
        expect(dec.progress, greaterThanOrEqualTo(previous),
            reason: 'progress fell at seq $seq');
        previous = dec.progress;
      }
    });
  });
}
