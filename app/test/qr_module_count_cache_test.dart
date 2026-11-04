/// Does counting a code's modules stay cheap enough to call from a build?
///
/// [qrModuleCount] answers by building a whole QR — a version search and a
/// Reed-Solomon matrix — because deriving the figure from the capacity table
/// was wrong by up to 16 modules. That is the right answer and an expensive
/// one, and the sending screen asks for it eleven times per frame:
/// `qrSizeAdvice` calls `pixelsPerModuleOnScreen` once and
/// `chunkUnlockedByABiggerWindow` twice, each of which loops over all four
/// chunk sizes.
///
/// Measured on 2026-11-04, a frame on an M3 spent 125.7 ms on the UI thread
/// against 2.3 ms rasterising, while drawing the one real code costs about
/// 17 ms. Eleven throwaway codes per frame is where the rest went.
///
/// The answer depends only on (chunkSize, ecLevel), both from small fixed
/// sets, so it is cached. These tests hold that: the first call may be slow,
/// the rest must not be.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/src/chunking.dart';
import 'package:dead_drop/src/qrframe.dart';

void main() {
  group('qrModuleCount is cached', () {
    test('a repeated call is far cheaper than the first', () {
      // The figure that matters is the ratio, not either time: a cached
      // lookup is a map read, and building the code is a version search
      // plus Reed-Solomon. Two orders of magnitude apart on any machine
      // this runs on, so 10x is a floor no uncached implementation meets
      // and no slow CI runner trips over.
      final cold = Stopwatch()..start();
      qrModuleCount(512, 'L');
      cold.stop();

      final warm = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        qrModuleCount(512, 'L');
      }
      warm.stop();

      final perWarmCall = warm.elapsedMicroseconds / 100;
      expect(
        perWarmCall * 10,
        lessThan(cold.elapsedMicroseconds),
        reason: 'a second call rebuilt the code instead of reading a cache; '
            'cold ${cold.elapsedMicroseconds}us, '
            'warm ${perWarmCall.toStringAsFixed(1)}us per call',
      );
    });

    test('one screenful of advice costs about one code, not eleven', () {
      // What the sending screen actually does per frame, in the shape it
      // does it: every chunk size at the level in force, three times over.
      // Warm the cache the way the first frame does, then time the rest.
      for (final size in kChunkSizeOptions) {
        qrModuleCount(size, 'L');
      }

      final oneCode = Stopwatch()..start();
      qrModuleCount(1024, 'H'); // a combination not yet asked for
      oneCode.stop();

      final aFrame = Stopwatch()..start();
      for (var pass = 0; pass < 3; pass++) {
        for (final size in kChunkSizeOptions) {
          qrModuleCount(size, 'L');
        }
      }
      aFrame.stop();

      expect(
        aFrame.elapsedMicroseconds,
        lessThan(oneCode.elapsedMicroseconds),
        reason: 'twelve cached lookups should not cost what one build does; '
            'frame ${aFrame.elapsedMicroseconds}us, '
            'one code ${oneCode.elapsedMicroseconds}us',
      );
    });

    test('the cached answers are the ones the encoder gives', () {
      // A cache that returns a wrong number is worse than a slow screen:
      // the module count is the denominator in every density warning, so
      // a wrong one warns about a code that is fine or stays quiet about
      // one that is not. These are the figures the encoder produced before
      // the cache existed.
      expect(qrModuleCount(256, 'L'), 73);
      expect(qrModuleCount(512, 'L'), 93);
      expect(qrModuleCount(1024, 'L'), 125);
      expect(qrModuleCount(2048, 'L'), 177);
      // The strongest level each size can still manage, because the
      // density warnings are decided at the top of this range.
      expect(qrModuleCount(256, 'H'), 105);
      expect(qrModuleCount(512, 'H'), 141);
      expect(qrModuleCount(1024, 'Q'), 169);
    });

    test('each error-correction level keeps its own answer', () {
      // Caching on the chunk size alone would hand L's module count to H,
      // which is the failure that makes a cache worse than no cache: the
      // same chunk needs a denser code at a stronger level.
      final atL = qrModuleCount(256, 'L')!;
      final atH = qrModuleCount(256, 'H')!;

      expect(atH, greaterThan(atL),
          reason: 'stronger error correction needs more modules');

      // Asked again, in the other order, from the cache.
      expect(qrModuleCount(256, 'H'), atH);
      expect(qrModuleCount(256, 'L'), atL);
    });

    test('a size no code can hold still reports nothing, every time', () {
      // The null is a real answer and has to cache like any other, or the
      // screen pays for the failed build on every frame — the slowest
      // path of all, since it is a full version search that finds nothing.
      // 1024 bytes at H is the smallest real combination that no version
      // can carry, so this is the path the sending screen can actually
      // reach, not a figure invented to be too big.
      expect(qrModuleCount(1024, 'H'), isNull);
      expect(qrModuleCount(1024, 'H'), isNull);
      expect(qrModuleCount(2048, 'M'), isNull);
    });

    test('an unknown level is rejected, not cached as a code', () {
      expect(qrModuleCount(256, 'Z'), isNull);
    });
  });
}
