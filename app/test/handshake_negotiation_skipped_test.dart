/// A hint that arrives before the screen is measured must not pass
/// through unchecked.
///
/// `applyReceiverHint` negotiates the receiver's suggestion against
/// what this screen can draw. The comment above that call says the
/// `> 0` guard "used to" skip the negotiation and was replaced by a
/// prediction — but the guard is still there, so a hint arriving with
/// no size known is applied in full.
///
/// It matters on a phone, where the handshake is scanned before any
/// code has been drawn. The failure is the one the function exists to
/// prevent: the sender agrees to a chunk size, starts emitting, and
/// only then says it cannot draw it.
///
/// A size of zero is not "any size is fine". It is "nothing is known",
/// and the safe reading of nothing is the smallest offered chunk, not
/// the largest the receiver asked for.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/chunking.dart';
import 'package:dead_drop/ui/send/send_page.dart';

void main() {
  group('negotiateSettings with no measured screen', () {
    test('an unknown size does not wave the request through', () {
      // The value applyReceiverHint's guard tests for.
      final agreed = negotiateSettings(
        requestedChunkSize: 2048,
        requestedEcLevel: 'L',
        displaySize: 0,
      );

      expect(agreed.chunkSize, lessThan(2048),
          reason: 'with no size known, agreeing to the densest option is '
              'the failure this negotiation exists to prevent');
      expect(agreed.chunkSize, kChunkSizeOptions.first,
          reason: 'nothing known means the smallest offered chunk, which '
              'every screen can draw');
    });

    test('a negative size is treated the same as none', () {
      final agreed = negotiateSettings(
        requestedChunkSize: 1024,
        requestedEcLevel: 'L',
        displaySize: -1,
      );

      expect(agreed.chunkSize, kChunkSizeOptions.first);
    });

    test('a request already at the floor is left alone', () {
      // The counterpart: refusing to raise is not the same as always
      // lowering. A receiver asking for the smallest chunk gets it.
      final agreed = negotiateSettings(
        requestedChunkSize: kChunkSizeOptions.first,
        requestedEcLevel: 'L',
        displaySize: 0,
      );

      expect(agreed.chunkSize, kChunkSizeOptions.first);
    });
  });

  group('negotiateSettings with a measured screen', () {
    // A Redmi Note 14 is width-bound: 1080 physical pixels at ~2.75
    // density is about 393 logical, and the code already fills it.
    const redmi = 393.0;

    test('the screen decides, not the chunk size alone', () {
      // Same request, two screens. Measured on 2026-11-05: this phone
      // transfers 1024 B and reads nothing at 2048.
      final onPhone = negotiateSettings(
        requestedChunkSize: 2048,
        requestedEcLevel: 'L',
        displaySize: redmi,
      );
      final onDesktop = negotiateSettings(
        requestedChunkSize: 2048,
        requestedEcLevel: 'L',
        displaySize: 578,
      );

      expect(onPhone.chunkSize, lessThan(2048),
          reason: '2048 B is 1.95 px per module here and read nothing');
      expect(onDesktop.chunkSize, greaterThan(onPhone.chunkSize));
    });
  });
}
