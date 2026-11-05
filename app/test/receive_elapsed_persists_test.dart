/// Does the time a transfer took survive the transfer ending?
///
/// It did not. The readout lived inside the progress block, which is
/// guarded by `sessionActive` — true while a receiver exists. Finishing
/// clears the receiver, the whole block goes, and the figure goes with
/// it, at the exact moment it stops changing and becomes worth reading.
///
/// Reported by the owner on 2026-11-04, who had spent the day timing
/// transfers by hand against a phone stopwatch while the app knew the
/// answer and threw it away.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/ui/elapsed_time.dart';
import 'package:dead_drop/ui/receive/receive_page.dart';

void main() {
  group('the completed transfer keeps its duration', () {
    test('the state carries both ends of the measurement', () {
      // Whatever the screen does with them, the figures have to exist
      // after the session is over, or no later screen can show them.
      final started = DateTime(2026, 11, 4, 12, 0, 0);
      final finished = started.add(const Duration(minutes: 1, seconds: 20));

      final state = ReceiveState(
        startedAt: started,
        completedAt: finished,
      );

      expect(state.startedAt, isNotNull);
      expect(state.completedAt, isNotNull);
      expect(
        state.completedAt!.difference(state.startedAt!),
        const Duration(minutes: 1, seconds: 20),
      );
    });

    test('transferDuration reports the elapsed time once finished', () {
      final started = DateTime(2026, 11, 4, 12, 0, 0);
      final state = ReceiveState(
        startedAt: started,
        completedAt: started.add(const Duration(minutes: 1, seconds: 20)),
      );

      expect(state.transferDuration, const Duration(minutes: 1, seconds: 20));
    });

    test('an unfinished transfer has no duration to report', () {
      // Not zero: a running transfer has no final figure, and reporting
      // 0:00 for one would be a lie that looks like a measurement.
      final state = ReceiveState(startedAt: DateTime(2026, 11, 4, 12));

      expect(state.transferDuration, isNull);
    });

    test('a transfer that never started has none either', () {
      expect(ReceiveState().transferDuration, isNull);
    });

    test('the duration formats the way the live readout does', () {
      // The same function, so the figure on the completed card cannot
      // drift into a different format from the one that was ticking a
      // second earlier.
      final started = DateTime(2026, 11, 4, 12, 0, 0);
      final state = ReceiveState(
        startedAt: started,
        completedAt: started.add(const Duration(minutes: 1, seconds: 20)),
      );

      expect(formatElapsed(state.transferDuration!), '1:20');
    });

    test('a clock that steps backwards reports nothing, not a negative', () {
      // DateTime.now() can go backwards across an NTP correction, and a
      // transfer takes minutes. "-0:03 taken" is worse than silence.
      final started = DateTime(2026, 11, 4, 12, 0, 0);
      final state = ReceiveState(
        startedAt: started,
        completedAt: started.subtract(const Duration(seconds: 3)),
      );

      expect(state.transferDuration, isNull);
    });
  });
}
