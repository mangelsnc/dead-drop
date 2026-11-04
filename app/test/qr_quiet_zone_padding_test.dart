/// The arithmetic behind the quiet zone.
///
/// qr_quiet_zone_test.dart renders the real screen and measures the
/// drawn pixels, which is what proves the margin reaches the user. This
/// one pins the function that computes it, because a widget test says
/// "four modules of margin appeared" without saying which of several
/// wrong formulas could also have produced that on one screen size.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/qrframe.dart';
import 'package:dead_drop/ui/send/send_page.dart';

void main() {
  group('qrQuietZonePadding', () {
    test('leaves four modules on each side, with the code in between', () {
      // The property that matters, stated as the layout it produces:
      // two margins plus the code fill the box, and each margin is four
      // modules of the same pitch the code is drawn at.
      const box = 578.0;
      const modules = 73;

      final padding = qrQuietZonePadding(displaySize: box, modules: modules);
      final codeWidth = box - 2 * padding;
      final pitch = codeWidth / modules;

      // Exactly four: the code is drawn at precisely this pitch (see
      // _scaledFromOnePixelPerModule), so any more is code size thrown
      // away and any less is under the standard.
      expect(padding / pitch, closeTo(4.0, 1e-9),
          reason: 'the margin is ${(padding / pitch).toStringAsFixed(2)} '
              'modules, not the four ISO/IEC 18004 requires');
    });

    test('scales with the code, rather than staying a fixed width', () {
      // The bug this replaces: qr_flutter's flat 10 logical pixels.
      // A constant is worth fewer modules the larger the code is drawn,
      // so it fails worst on the big screens that should be easiest.
      const modules = 73;
      final small = qrQuietZonePadding(displaySize: 300, modules: modules);
      final large = qrQuietZonePadding(displaySize: 900, modules: modules);

      expect(large, greaterThan(small * 2),
          reason: 'tripling the drawn size left the margin at $small -> '
              '$large px, so it is not tracking the module pitch');
    });

    test('a denser code gets a wider margin in the same box', () {
      // Same screen, more modules: each module is smaller, so four of
      // them is fewer pixels -- but the ratio must hold either way.
      const box = 578.0;
      final sparse = qrQuietZonePadding(displaySize: box, modules: 73);
      final dense = qrQuietZonePadding(displaySize: box, modules: 177);

      expect(dense, lessThan(sparse),
          reason: 'a denser code has a smaller module, so four modules of '
              'margin is fewer pixels: $sparse -> $dense');

      final densePitch = (box - 2 * dense) / 177;
      expect(dense / densePitch, closeTo(4.0, 1e-9));
    });

    test('the margin never eats the box', () {
      // A formula that solved for the pitch before subtracting the
      // margin asks for more room than it was given. At the extreme --
      // the densest code this app emits in the smallest box it draws --
      // the code must still have most of the space.
      final padding = qrQuietZonePadding(displaySize: 200, modules: 177);
      expect(2 * padding, lessThan(200 * 0.5),
          reason: 'the margins take ${2 * padding} px of a 200 px box, '
              'leaving the code less than half');
    });

    test('degenerate inputs give nothing rather than a negative margin', () {
      expect(qrQuietZonePadding(displaySize: 0, modules: 73), 0);
      expect(qrQuietZonePadding(displaySize: 578, modules: 0), 0);
      expect(qrQuietZonePadding(displaySize: -10, modules: 73), 0);
    });
  });

  group('pixelsPerModuleOnScreen', () {
    test('divides the whole box, quiet zone included', () {
      // Not the pitch the modules are drawn at: the margin comes out of
      // the box first. Pinned as it is because
      // kMinUsablePixelsPerModule was fitted to this denominator
      // against a Redmi Note 14 -- 512 B at 3.29 transferred nothing,
      // 256 B at 4.26 finished in a minute. Correcting one without
      // re-measuring the other makes the app refuse a setting that was
      // watched working. This test fails if someone changes it alone.
      const box = 578.0;
      final density = pixelsPerModuleOnScreen(
        displaySize: box,
        chunkSize: 256,
        ecLevel: 'L',
      );

      final modules = qrModuleCount(256, 'L')!;
      expect(density, closeTo(box / modules, 0.001));
    });

    test('the calibration the floor was fitted to still holds', () {
      // The two measured outcomes, as numbers rather than prose. If a
      // change moves either across kMinUsablePixelsPerModule, the floor
      // needs re-measuring on hardware, not recomputing.
      const redmi = 345.0;
      final at512 = pixelsPerModuleOnScreen(
        displaySize: redmi,
        chunkSize: 512,
        ecLevel: 'M',
      );
      final at256 = pixelsPerModuleOnScreen(
        displaySize: redmi,
        chunkSize: 256,
        ecLevel: 'M',
      );

      expect(at512, closeTo(3.29, 0.01),
          reason: 'the chunk size measured as unreadable on a Redmi Note '
              '14 no longer reads as 3.29 px per module');
      expect(at256, closeTo(4.26, 0.01),
          reason: 'the chunk size measured as working on a Redmi Note 14 '
              'no longer reads as 4.26 px per module');
      expect(at512, lessThan(kMinUsablePixelsPerModule));
      expect(at256, greaterThanOrEqualTo(kMinUsablePixelsPerModule));
    });

    test('an unencodable chunk has no density', () {
      // 2048 B at EC-H does not fit any version.
      expect(
        pixelsPerModuleOnScreen(
          displaySize: 578,
          chunkSize: 2048,
          ecLevel: 'H',
        ),
        0,
      );
    });
  });
}
