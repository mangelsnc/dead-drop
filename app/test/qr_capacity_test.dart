/// A chunk size and an error-correction level have to produce a QR that
/// can actually be drawn.
///
/// Reported from a phone: "at 2048 bytes the screen breaks when showing
/// QRs". A frame that size encodes to about 2,860 characters, and the
/// largest QR holds 2,953 at level L but only 2,331 at M — the default.
/// Asking for more than version 40 can carry fails the render outright,
/// so the combination has to be unreachable rather than merely unwise.
library;

import 'package:dead_drop/src/chunking.dart';
import 'package:dead_drop/src/qrframe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what fits in a QR', () {
    test('the default chunk fits at every level', () {
      for (final ec in ['L', 'M', 'Q', 'H']) {
        expect(chunkFitsQr(kDefaultChunkSize, ec), isTrue, reason: ec);
      }
    });

    test('2048 bytes fits only at L', () {
      expect(ecLevelsFor(2048), ['L'],
          reason: 'this is the combination that broke the display');
    });

    test('1024 bytes fits at everything but H', () {
      expect(ecLevelsFor(1024), ['Q', 'M', 'L']);
    });

    test('every offered chunk size is renderable at some level', () {
      for (final size in kChunkSizeOptions) {
        expect(ecLevelsFor(size), isNotEmpty,
            reason: '$size bytes can never be shown, so offering it is a '
                'trap — 4096 was exactly that until it was removed');
      }
    });

    test('4096 is not offered, because nothing can carry it', () {
      expect(kChunkSizeOptions, isNot(contains(4096)));
      expect(ecLevelsFor(4096), isEmpty);
    });
  });

  group('the estimate is an upper bound', () {
    test('it grows with the chunk', () {
      expect(encodedFrameChars(512), greaterThan(encodedFrameChars(256)));
      expect(encodedFrameChars(2048), greaterThan(encodedFrameChars(1024)));
    });

    test('it allows for base64 expansion', () {
      // 4 characters per 3 bytes, so the encoded form is always larger
      // than the chunk it carries.
      expect(encodedFrameChars(1024), greaterThan(1024 * 4 ~/ 3));
    });
  });
}
