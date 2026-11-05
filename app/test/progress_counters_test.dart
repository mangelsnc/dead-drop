/// The receive screen's two counters mean different things.
///
/// It reports "N / total chunks (M frames scanned)". The first can never
/// exceed the total; the second routinely does, because a fountain code
/// needs more frames than chunks. Reported as "it has read more chunks
/// than the file had", which is what the second number looks like if it
/// is taken for the first.
library;

import 'dart:typed_data';

import 'package:dead_drop/src/fountain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decoded chunk count', () {
    test('never exceeds the number of chunks in the file', () {
      // Feed far more frames than the file needs and check the count
      // stops at k. If it ever passed k the progress bar would read
      // over 100% and the file would be wrong.
      for (final k in [10, 100]) {
        final chunks = List.generate(k, (i) {
          final b = Uint8List(32);
          b[0] = i & 0xff;
          b[1] = (i >> 8) & 0xff;
          return b;
        });
        final enc = LTEncoder(chunks);
        final dec = LTDecoder(k: k, chunkSize: 32);

        for (var seq = 1; seq <= k * 10; seq++) {
          final (ids, payload) = enc.makeFrame(seq, 4242);
          dec.addFrame(ids, payload);
          expect(
            dec.decoded.length,
            lessThanOrEqualTo(k),
            reason: 'k=$k after $seq frames',
          );
        }
        expect(dec.decoded.length, k, reason: 'k=$k should finish');
      }
    });

    test('more frames are consumed than there are chunks', () {
      // The control, and the reason the two numbers differ: a fountain
      // code is not one frame per chunk. If this ever stopped being
      // true the test above would prove nothing about the distinction.
      const k = 100;
      final chunks = List.generate(k, (i) {
        final b = Uint8List(32);
        b[0] = i & 0xff;
        b[1] = (i >> 8) & 0xff;
        return b;
      });
      final enc = LTEncoder(chunks);
      final dec = LTDecoder(k: k, chunkSize: 32);

      var frames = 0;
      for (var seq = 1; seq <= k * 20 && !dec.done; seq++) {
        final (ids, payload) = enc.makeFrame(seq, 4242);
        dec.addFrame(ids, payload);
        frames++;
      }
      expect(dec.done, isTrue);
      expect(frames, greaterThan(k),
          reason: 'frames scanned legitimately exceeds the chunk count');
    });
  });
}
