/// Does the sender show the rate it achieves, or the rate it was asked for?
///
/// The sending screen printed "10 fps" because 10 was the configured
/// value, never because ten codes reached the screen in a second. On a
/// Linux laptop the codes visibly changed about four times a second with
/// the setting at ten, and nothing on screen said so: the number agreed
/// with the slider and disagreed with the display.
///
/// That is the same mistake already fixed once on the receiving side,
/// where a counter reported a figure it could not have measured. A
/// setting is a request; only a measurement is a fact.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/ui/send/send_page.dart';

void main() {
  group('measuring what the screen actually emits', () {
    test('nothing is claimed before there is enough to measure', () {
      final rate = EmissionRate();

      expect(rate.measuredFps, isNull,
          reason: 'a figure from one or two frames is noise, and the '
              'screen would rather say nothing than say something it '
              'cannot support');

      rate.recordFrame(at: DateTime(2026, 1, 1, 0, 0, 0));
      rate.recordFrame(at: DateTime(2026, 1, 1, 0, 0, 0, 100));

      expect(rate.measuredFps, isNull);
    });

    test('a steady ten per second measures as ten', () {
      final rate = EmissionRate();
      var t = DateTime(2026, 1, 1);
      for (var i = 0; i < 12; i++) {
        rate.recordFrame(at: t);
        t = t.add(const Duration(milliseconds: 100));
      }

      expect(rate.measuredFps, isNotNull);
      expect(rate.measuredFps!, closeTo(10, 0.5));
    });

    test('a screen that cannot keep up measures lower than the setting', () {
      // The Linux case: asked for ten, manages about four.
      final rate = EmissionRate();
      var t = DateTime(2026, 1, 1);
      for (var i = 0; i < 12; i++) {
        rate.recordFrame(at: t);
        t = t.add(const Duration(milliseconds: 250));
      }

      expect(rate.measuredFps!, closeTo(4, 0.5),
          reason: 'this is the whole point: the sender has to be able to '
              'say that ten were asked for and four arrived');
    });

    test('one slow frame does not move the figure', () {
      // A garbage-collection pause or a window being dragged. The median
      // is used for the same reason the receiver uses one.
      final rate = EmissionRate();
      var t = DateTime(2026, 1, 1);
      for (var i = 0; i < 12; i++) {
        rate.recordFrame(at: t);
        // One frame arrives two seconds late, the rest at 100 ms.
        t = t.add(i == 6
            ? const Duration(milliseconds: 2000)
            : const Duration(milliseconds: 100));
      }

      expect(rate.measuredFps!, closeTo(10, 1.0),
          reason: 'a mean would read about 5 here, which describes no '
              'moment of the transfer');
    });

    test('restarting forgets the old rate', () {
      // Changing the frame rate restarts the timer; carrying the old
      // measurement across would blend two different settings.
      final rate = EmissionRate();
      var t = DateTime(2026, 1, 1);
      for (var i = 0; i < 12; i++) {
        rate.recordFrame(at: t);
        t = t.add(const Duration(milliseconds: 250));
      }
      expect(rate.measuredFps, isNotNull);

      rate.reset();

      expect(rate.measuredFps, isNull);
    });
  });
}
