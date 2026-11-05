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

    test('the floor matches what the hardware did', () {
      // Measured on 2026-11-05, Redmi Note 14 emitting to a MacBook and
      // a Slimbook, all at EC-L, after the quiet-zone fix. These are
      // outcomes, not predictions: every row was watched.
      //
      //   256 B  4.73 px/module  transfers
      //   512 B  3.71            1 min 11 s
      //  1024 B  2.76            28 s -- the project's best result
      //  2048 B  1.95            does not read
      //
      // So the floor lies between 1.95 and 2.76, which agrees with the
      // decoder theory already written on pixelsPerModuleOnScreen: about
      // three samples per module wanted, two the hard limit.
      //
      // The previous floor of 4.0 was fitted before the emitted code had
      // a quiet zone, so it was calibrated against a different defect:
      // it refused 1024 B, the fastest configuration there is.
      const redmi = 345.0;
      double at(int chunk) => pixelsPerModuleOnScreen(
            displaySize: redmi,
            chunkSize: chunk,
            ecLevel: 'L',
          );

      expect(at(1024), closeTo(2.76, 0.01),
          reason: 'the fastest configuration measured on hardware no '
              'longer reads as 2.76 px per module');
      expect(at(2048), closeTo(1.95, 0.01),
          reason: 'the configuration that would not read no longer reads '
              'as 1.95 px per module');

      // The floor has to admit what worked and refuse what did not.
      expect(at(1024), greaterThanOrEqualTo(kMinUsablePixelsPerModule),
          reason: '1024 B transferred a file in 28 seconds; the floor '
              'must not refuse it');
      expect(at(2048), lessThan(kMinUsablePixelsPerModule),
          reason: '2048 B did not read; the floor must still refuse it');

      // And it must stay above the decoder's hard limit, whatever else
      // is measured later.
      expect(kMinUsablePixelsPerModule, greaterThan(2.0),
          reason: 'below two samples per module no decoder can work');
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
